#!/usr/bin/env bats
# Tests for install_config_any_zfs (ADR 0043) — the derived predicate that is
# true when ANY group (root, storage_groups[], data_pools[]) uses ZFS. It gates
# zfs userland, the boot-time pool import, the ZFS Module Guard, and the
# archzfs-compatible ISO requirement: a machine with no ZFS group anywhere needs
# none of them; an ext4 root with a ZFS data pool still does. Pure: reads
# CONFIG_FILE only.

setup() {
  TEST_DIR="$(mktemp -d)"
  export CONFIG_FILE="$TEST_DIR/install.jsonc"
  jsonc_strip() { cat "$1"; }
  jsonc_read() { jsonc_strip "$1" | jq -r "$2"; }
  cfgo() { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  error() { echo "ERROR: $*" >&2; exit 1; }
  export -f jsonc_strip jsonc_read cfgo error

  # shellcheck source=../../lib/config/accessors.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/accessors.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

write_config() { printf '%s\n' "$1" > "$CONFIG_FILE"; }

@test "any_zfs: the default (zfs root, no groups) is true" {
  write_config '{}'
  run install_config_any_zfs
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "any_zfs: ext4 root with no groups is false" {
  write_config '{"filesystem":"ext4"}'
  run install_config_any_zfs
  [ "$output" = "false" ]
}

@test "any_zfs: ext4 root with a zfs data pool is true" {
  write_config '{"filesystem":"ext4",
    "data_pools":[{"name":"tank0","filesystem":"zfs"}]}'
  run install_config_any_zfs
  [ "$output" = "true" ]
}

@test "any_zfs: ext4 root with a zfs storage group is true" {
  write_config '{"filesystem":"ext4",
    "storage_groups":[{"name":"bulk","filesystem":"zfs"}]}'
  run install_config_any_zfs
  [ "$output" = "true" ]
}

@test "any_zfs: btrfs root with all-ext4 data is false" {
  write_config '{"filesystem":"btrfs",
    "data_pools":[{"name":"tank0","filesystem":"ext4"}],
    "storage_groups":[{"name":"bulk","filesystem":"xfs"}]}'
  run install_config_any_zfs
  [ "$output" = "false" ]
}

@test "any_zfs: a data pool inheriting a zfs root counts as zfs" {
  write_config '{"data_pools":[{"name":"tank0"}]}'
  run install_config_any_zfs
  [ "$output" = "true" ]
}

# ── install_config_any_nonzfs_luks — gates cryptsetup + the boot crypttab ────
# True when the root OR any data pool is a non-zfs ENCRYPTED group (zfs uses
# native crypto, not LUKS). A zfs root with an encrypted ext4 data disk still
# needs cryptsetup on the target even though the root itself is unencrypted.

@test "any_luks: zfs root + encrypted ext4 data pool is true" {
  write_config '{"data_pools":[{"name":"tank0","filesystem":"ext4",
    "encryption":true}]}'
  run install_config_any_nonzfs_luks
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "any_luks: plaintext non-zfs groups are false" {
  write_config '{"data_pools":[{"name":"tank0","filesystem":"ext4"}]}'
  run install_config_any_nonzfs_luks
  [ "$output" = "false" ]
}

@test "any_luks: an encrypted zfs data pool is false (native crypto)" {
  write_config '{"data_pools":[{"name":"tank0","filesystem":"zfs",
    "encryption":true}]}'
  run install_config_any_nonzfs_luks
  [ "$output" = "false" ]
}

@test "any_luks: an encrypted ext4 root is true" {
  write_config '{"filesystem":"ext4","options":{"encryption":true}}'
  run install_config_any_nonzfs_luks
  [ "$output" = "true" ]
}
