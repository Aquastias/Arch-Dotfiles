#!/usr/bin/env bats
# Tests for .os/lib/finalize.sh — post-install cleanup.
#
# Strategy: stub zpool / zfs / umount as bash fns that append argv to $CALLS,
# then source finalize.sh and call finalize. Assertions read $CALLS.

setup() {
  TEST_DIR="$(mktemp -d)"
  CALLS="$TEST_DIR/calls.log"
  export TEST_DIR CALLS

  info()    { :; }
  warn()    { :; }
  section() { :; }
  export -f info warn section

  zpool()  { printf 'zpool %s\n'  "$*" >> "$CALLS"; }
  zfs()    { printf 'zfs %s\n'    "$*" >> "$CALLS"; }
  umount() { printf 'umount %s\n' "$*" >> "$CALLS"; }
  export -f zpool zfs umount

  export MOUNT_ROOT="$TEST_DIR/mnt"
  LAYOUT_ESP_PARTS=()
  export LAYOUT_ESP_PARTS

  # shellcheck source=../lib/finalize.sh
  source "$BATS_TEST_DIRNAME/../lib/finalize.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# ── slice 1: only OS pool set ────────────────────────────────────────────────

@test "exports os pool when only LAYOUT_OS_POOL_NAME is set" {
  export LAYOUT_OS_POOL_NAME=rpool
  export LAYOUT_DATA_POOL_NAME=""
  finalize >/dev/null
  grep -qx 'zpool export rpool' "$CALLS"
}

@test "skips data pool export when LAYOUT_DATA_POOL_NAME is empty" {
  export LAYOUT_OS_POOL_NAME=rpool
  export LAYOUT_DATA_POOL_NAME=""
  finalize >/dev/null
  [ "$(grep -c '^zpool export ' "$CALLS")" -eq 1 ]
}

# ── slice 2: both pools set ──────────────────────────────────────────────────

@test "exports both pools when LAYOUT_DATA_POOL_NAME is also set" {
  export LAYOUT_OS_POOL_NAME=rpool
  export LAYOUT_DATA_POOL_NAME=tank
  finalize >/dev/null
  grep -qx 'zpool export rpool' "$CALLS"
  grep -qx 'zpool export tank'  "$CALLS"
  [ "$(grep -c '^zpool export ' "$CALLS")" -eq 2 ]
}
