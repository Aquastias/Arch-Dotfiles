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

# ── only OS pool set (no data pools) ─────────────────────────────────────────

@test "exports os pool when no data pools are set" {
  LAYOUT_OS_POOL_NAME=rpool
  LAYOUT_DATA_POOL_NAMES=()
  finalize >/dev/null
  grep -qx 'zpool export rpool' "$CALLS"
}

@test "exports only the os pool when LAYOUT_DATA_POOL_NAMES is empty" {
  LAYOUT_OS_POOL_NAME=rpool
  LAYOUT_DATA_POOL_NAMES=()
  finalize >/dev/null
  [ "$(grep -c '^zpool export ' "$CALLS")" -eq 1 ]
}

# ── multiple data pools (combined dpool + standalones) ───────────────────────

@test "exports the os pool and every pool in LAYOUT_DATA_POOL_NAMES" {
  LAYOUT_OS_POOL_NAME=rpool
  LAYOUT_DATA_POOL_NAMES=(dpool tank0 tank1)
  finalize >/dev/null
  grep -qx 'zpool export rpool' "$CALLS"
  grep -qx 'zpool export dpool' "$CALLS"
  grep -qx 'zpool export tank0' "$CALLS"
  grep -qx 'zpool export tank1' "$CALLS"
  [ "$(grep -c '^zpool export ' "$CALLS")" -eq 4 ]
}

@test "recovery hint lists the os pool and each data pool" {
  LAYOUT_OS_POOL_NAME=rpool
  LAYOUT_DATA_POOL_NAMES=(tank0 tank1)
  run finalize
  [[ "$output" == *"zpool import -f rpool"* ]]
  [[ "$output" == *"zpool import -f tank0"* ]]
  [[ "$output" == *"zpool import -f tank1"* ]]
}
