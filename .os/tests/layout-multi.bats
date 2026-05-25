#!/usr/bin/env bats
# Tests for .os/lib/layout-multi.sh — pure topology suggestion functions.
# suggest_os_topologies and suggest_storage_topologies have no system calls.

setup() {
  TEST_DIR="$(mktemp -d)"
  CONFIG_FILE="$TEST_DIR/install.json"
  export CONFIG_FILE
  printf '{}' > "$CONFIG_FILE"
  # shellcheck source=../lib/common.sh
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
  # shellcheck source=../lib/zfs-pools.sh
  source "$BATS_TEST_DIRNAME/../lib/zfs-pools.sh"
  # shellcheck source=../lib/layout-multi.sh
  source "$BATS_TEST_DIRNAME/../lib/layout-multi.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── suggest_os_topologies ─────────────────────────────────────────────────────

@test "suggest_os_topologies(1): emits exactly one line" {
  run suggest_os_topologies 1
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l)" -eq 1 ]
}

@test "suggest_os_topologies(1): the single option is none" {
  run suggest_os_topologies 1
  [ "$status" -eq 0 ]
  [[ "$output" == none* ]]
}

@test "suggest_os_topologies(2): first recommendation is mirror" {
  run suggest_os_topologies 2
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | head -1)" == mirror* ]]
}

@test "suggest_os_topologies(3): includes mirror as an option" {
  run suggest_os_topologies 3
  [ "$status" -eq 0 ]
  [[ "$output" == *mirror* ]]
}

# ── suggest_storage_topologies ────────────────────────────────────────────────

@test "suggest_storage_topologies(1): first recommendation is independent" {
  run suggest_storage_topologies 1
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | head -1)" == independent* ]]
}

@test "suggest_storage_topologies(2): first recommendation is mirror" {
  run suggest_storage_topologies 2
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | head -1)" == mirror* ]]
}

@test "suggest_storage_topologies(3): first recommendation is raidz1" {
  run suggest_storage_topologies 3
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | head -1)" == raidz1* ]]
}

@test "suggest_storage_topologies(4): first recommendation is raidz1" {
  run suggest_storage_topologies 4
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | head -1)" == raidz1* ]]
}

@test "suggest_storage_topologies(5): first recommendation is raidz2" {
  run suggest_storage_topologies 5
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | head -1)" == raidz2* ]]
}

@test "suggest_storage_topologies(6): first recommendation is raidz2" {
  run suggest_storage_topologies 6
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | head -1)" == raidz2* ]]
}

# ── phase lifecycle smoke (ADR 0016) ────────────────────────────────────────
# Drives the full seam chain through both wrappers and asserts
# _LAYOUT_PHASE reaches the final ordinal. Stubs external commands and the
# zfs-pools.sh / install-config.sh seams the same way layout-single.bats does.

setup_phase_smoke_fixture() {
  CALLS="$TEST_DIR/calls.log"
  export CALLS MOUNT_ROOT="$TEST_DIR/mnt"
  mkdir -p "$MOUNT_ROOT"

  cat >"$CONFIG_FILE" <<'JSONC'
{
  "os_pool":  { "pool_name": "rpool",
                "topology":  "mirror",
                "disks":     ["/dev/sdx", "/dev/sdy"] },
  "storage_groups": []
}
JSONC

  # shellcheck source=../lib/install-config.sh
  source "$BATS_TEST_DIRNAME/../lib/install-config.sh"

  info()    { :; }
  warn()    { :; }
  section() { :; }
  confirm() { :; }
  pick_option() { PICK_RESULT="${2:-mirror}"; }

  wipefs()    { printf 'wipefs %s\n'    "$*" >>"$CALLS"; }
  sgdisk()    { printf 'sgdisk %s\n'    "$*" >>"$CALLS"; }
  partprobe() { printf 'partprobe %s\n' "$*" >>"$CALLS"; }
  mkfs.fat()  { printf 'mkfs.fat %s\n'  "$*" >>"$CALLS"; }
  mount()     { printf 'mount %s\n'     "$*" >>"$CALLS"; }
  lsblk()     { echo "?"; }
  sleep()     { :; }
  part_name() { printf '%s%s' "$1" "$2"; }

  build_enc_opts()      { :; }
  _zpool_create()       { printf '_zpool_create %s\n'       "$*" >>"$CALLS"; }
  _create_os_datasets() { printf '_create_os_datasets %s\n' "$*" >>"$CALLS"; }
  zfs()                 { printf 'zfs %s\n'                 "$*" >>"$CALLS"; }
  zpool()               { printf 'zpool %s\n'               "$*" >>"$CALLS"; }
}

@test "phase lifecycle: full chain leaves _LAYOUT_PHASE=5" {
  setup_phase_smoke_fixture
  layout_plan
  layout_partition
  layout_create_pools
  layout_mount_esp
  [ "$_LAYOUT_PHASE" -eq 5 ]
}

@test "phase lifecycle: layout_partition before layout_plan errors" {
  setup_phase_smoke_fixture
  run layout_partition
  [ "$status" -ne 0 ]
  [[ "$output" == *"out of order"* ]]
}
