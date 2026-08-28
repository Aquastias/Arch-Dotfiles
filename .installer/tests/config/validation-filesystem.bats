#!/usr/bin/env bats
# Tests for _validation_filesystem() in lib/config/validation.sh — the
# Filesystem Adapter contract checks (ADR 0040). Independent rules over the
# `filesystem` discriminator: the value is known; the encryption method matches
# the filesystem; impermanence is offered only on snapshotting filesystems.
# Whether a known filesystem is actually *built* is the layout-dispatch seam's
# job (only ZFS is implemented) — these checks are config-sanity only, so they
# accept/reject every filesystem independently and stay correct as adapters land.
#
# Strategy mirrors validation-impermanence.bats: stub common helpers, drive the
# accessors from CONFIG_FILE, assert error() fires (exit 1) on a bad combination.

setup() {
  TEST_DIR="$(mktemp -d)"
  export CONFIG_FILE="$TEST_DIR/install.jsonc"
  jsonc_strip() { cat "$1"; }
  jsonc_read() { jsonc_strip "$1" | jq -r "$2"; }
  cfgo()    { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  cfg()     { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  error()   { echo "ERROR: $*" >&2; exit 1; }
  info()    { :; }
  section() { :; }
  warn()    { :; }
  export -f jsonc_strip jsonc_read cfgo cfg error info section warn

  # shellcheck source=../../lib/config/accessors.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/accessors.sh"
  # shellcheck source=../../lib/config/validation.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/validation.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

write_config() { printf '%s\n' "$1" > "$CONFIG_FILE"; }

# ── known value: zfs (the default) passes; an unknown filesystem is rejected ─

@test "filesystem: zfs (the default) passes the contract" {
  write_config '{}'
  run _validation_filesystem
  [ "$status" -eq 0 ]
}

@test "filesystem: an unknown filesystem is rejected, naming the field" {
  write_config '{"filesystem":"reiserfs"}'
  run _validation_filesystem
  [ "$status" -ne 0 ]
  [[ "$output" =~ "filesystem" ]]
}

# ── encryption method must match the filesystem (zfs→native, else→luks) ──────

@test "method: zfs with an explicit native method passes" {
  write_config '{"filesystem":"zfs","options":{"encryption_method":"native"}}'
  run _validation_filesystem
  [ "$status" -eq 0 ]
}

@test "method: zfs with luks is rejected, naming the method path" {
  write_config '{"filesystem":"zfs","options":{"encryption_method":"luks"}}'
  run _validation_filesystem
  [ "$status" -ne 0 ]
  [[ "$output" =~ "encryption_method" ]]
}

@test "method: a non-zfs filesystem with the derived luks method passes" {
  write_config '{"filesystem":"btrfs"}'   # encryption_method derives to luks
  run _validation_filesystem
  [ "$status" -eq 0 ]
}

@test "method: a non-zfs filesystem with native is rejected" {
  write_config '{"filesystem":"btrfs","options":{"encryption_method":"native"}}'
  run _validation_filesystem
  [ "$status" -ne 0 ]
  [[ "$output" =~ "encryption_method" ]]
}

# ── impermanence is offered only on snapshotting filesystems (zfs / btrfs) ───

@test "impermanence: enabled on zfs passes" {
  write_config '{"filesystem":"zfs","options":{"impermanence":{"enabled":true}}}'
  run _validation_filesystem
  [ "$status" -eq 0 ]
}

@test "impermanence: enabled on btrfs passes" {
  write_config '{"filesystem":"btrfs",
    "options":{"impermanence":{"enabled":true}}}'
  run _validation_filesystem
  [ "$status" -eq 0 ]
}

@test "impermanence: enabled on ext4 is rejected, naming the path" {
  write_config '{"filesystem":"ext4",
    "options":{"impermanence":{"enabled":true}}}'
  run _validation_filesystem
  [ "$status" -ne 0 ]
  [[ "$output" =~ "impermanence" ]]
}

@test "impermanence: disabled on xfs passes (no snapshot requirement)" {
  write_config '{"filesystem":"xfs",
    "options":{"impermanence":{"enabled":false}}}'
  run _validation_filesystem
  [ "$status" -eq 0 ]
}
