#!/usr/bin/env bats
# Tests for .installer/lib/finalize.sh — post-install cleanup.
#
# Strategy: stub zpool / zfs / umount as bash fns that append argv to $CALLS,
# then source finalize.sh and call finalize. Assertions read $CALLS.

setup() {
  TEST_DIR="$(mktemp -d)"
  CALLS="$TEST_DIR/calls.log"
  export TEST_DIR CALLS

  # finalize.sh runs inside the installer with common.sh loaded (it uses
  # command_exists and the BOLD colour var). Source it first, then override
  # the log helpers below with silencing stubs so output stays clean.
  # shellcheck source=../lib/common.sh
  source "$BATS_TEST_DIRNAME/../lib/common.sh"

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

# ── _finalize_nonzfs_mounts (pure: which mounts to drop before export) ────────
# A non-zfs data-group mount (ext4/xfs/btrfs) under ${MOUNT_ROOT} holds it busy,
# so `zpool export` fails and the pool stays active → the initramfs import
# panics next boot ("previously in use from another system"). finalize must
# unmount these NON-zfs mounts first, deepest-path-first. Input is
# `findmnt -rno TARGET,FSTYPE`.

@test "nonzfs_mounts: returns the non-zfs data mount, drops zfs ones" {
  run _finalize_nonzfs_mounts <<<"/mnt zfs
/mnt/home zfs
/mnt/data/tank0 xfs"
  [ "$status" -eq 0 ]
  [ "$output" = "/mnt/data/tank0" ]
}

@test "nonzfs_mounts: all-zfs tree yields nothing" {
  run _finalize_nonzfs_mounts <<<"/mnt zfs
/mnt/home zfs"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "nonzfs_mounts: deepest path first (nested unmount order)" {
  run _finalize_nonzfs_mounts <<<"/mnt zfs
/mnt/data ext4
/mnt/data/sub btrfs"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | head -1)" = "/mnt/data/sub" ]
}

# ── a busy pool (Audit Run 20261004: greetd/tuned never imported at boot) ────

@test "a busy rpool is retried, then its users killed, then forced" {
  LAYOUT_OS_POOL_NAME=rpool
  LAYOUT_DATA_POOL_NAMES=()
  zpool() { printf 'zpool %s\n' "$*" >> "$CALLS"
    [[ "$*" == "export -f rpool" ]]; }      # only the forced export works
  fuser() { printf 'fuser %s\n' "$*" >> "$CALLS"; }
  findmnt() { echo '/mnt rpool/ROOT/arch'; }
  sleep() { :; }
  warn() { echo "WARN $*" >> "$CALLS"; }
  finalize >/dev/null
  grep -q '^fuser -km' "$CALLS"
  grep -qx 'zpool export -f rpool' "$CALLS"
  [ "$(grep -c '^zpool export rpool$' "$CALLS")" -ge 2 ]
  ! grep -q 'Could not export' "$CALLS"
}

@test "a pool that exports at once is neither killed nor forced" {
  LAYOUT_OS_POOL_NAME=rpool
  LAYOUT_DATA_POOL_NAMES=()
  fuser() { printf 'fuser %s\n' "$*" >> "$CALLS"; }
  finalize >/dev/null
  ! grep -q '^fuser\|export -f' "$CALLS"
}

@test "the kill step only touches the pool's own mounts, never the ISO root" {
  # laptop 20261005: `fuser -km /mnt` after /mnt was unmounted hit the live
  # ISO's root filesystem and killed the installer itself
  LAYOUT_OS_POOL_NAME=rpool
  LAYOUT_DATA_POOL_NAMES=()
  zpool() { printf 'zpool %s\n' "$*" >> "$CALLS"
    [[ "$*" == "export -f rpool" ]]; }
  findmnt() { printf '%s\n' "/mnt/home rpool/home" "/ airootfs"; }
  fuser() { printf 'fuser %s\n' "$*" >> "$CALLS"; }
  sleep() { :; }
  finalize >/dev/null
  grep -qx 'fuser -km /mnt/home' "$CALLS"
  ! grep -q 'fuser -km /mnt$\|fuser -km /$' "$CALLS"
}

@test "no zfs mounts left does not fire the installer's ERR trap" {
  # refind/ufw 20261006: findmnt (rc 1, nothing matched) in the kill step's
  # process substitution tripped the inherited ERR trap: "Installer failed"
  LAYOUT_OS_POOL_NAME=rpool
  LAYOUT_DATA_POOL_NAMES=()
  zpool() { [[ "$*" == "export -f rpool" ]]; }
  findmnt() { return 1; }
  sleep() { :; }
  set -E
  trap 'echo TRAP >> "$CALLS"' ERR
  finalize >/dev/null
  trap - ERR
  ! grep -q TRAP "$CALLS"
}

@test "processes chrooted into the target are killed before the retry" {
  # an arch-chroot leftover (gpg-agent…) holds the pool with no mount to fuser
  LAYOUT_OS_POOL_NAME=rpool
  LAYOUT_DATA_POOL_NAMES=()
  mkdir -p "$MOUNT_ROOT" "$TEST_DIR/proc/41" "$TEST_DIR/proc/42"
  ln -s "$MOUNT_ROOT" "$TEST_DIR/proc/41/root"
  ln -s / "$TEST_DIR/proc/42/root"
  FINALIZE_PROC="$TEST_DIR/proc"
  zpool() { printf 'zpool %s\n' "$*" >> "$CALLS"
    grep -q '^kill' "$CALLS"; }             # exports once the holder is gone
  kill() { printf 'kill %s\n' "$*" >> "$CALLS"; }
  findmnt() { return 1; }
  sleep() { :; }
  finalize >/dev/null
  grep -qx 'kill -KILL 41' "$CALLS"
  ! grep -q 'kill -KILL 42' "$CALLS"
  ! grep -q 'export -f' "$CALLS"
}

@test "a pool that never exports logs zpool's reason" {
  LAYOUT_OS_POOL_NAME=rpool
  LAYOUT_DATA_POOL_NAMES=()
  zpool() { echo "cannot export 'rpool': pool is busy" >&2; return 1; }
  findmnt() { return 1; }
  sleep() { :; }
  warn() { echo "WARN $*" >> "$CALLS"; }
  finalize >/dev/null 2>&1
  grep -q "WARN .*pool is busy" "$CALLS"
  grep -q "WARN Could not export rpool" "$CALLS"
}
