#!/usr/bin/env bats
# Tests for .os/lib/layout/single.sh — single-disk Layout Module seams.
#
# Strategy: stub external commands (blockdev/wipefs/sgdisk/...) and the
# zfs-pools.sh seam (_zpool_create / _create_os_datasets / build_enc_opts)
# as bash fns appending argv to $CALLS. Assert only on $CALLS plus the
# published LAYOUT_* state — never on _LAYOUT_IMPL_* internals.

setup() {
  TEST_DIR="$(mktemp -d)"
  CONFIG_FILE="$TEST_DIR/install.json"
  CALLS="$TEST_DIR/calls.log"
  export CONFIG_FILE CALLS
  export MOUNT_ROOT="$TEST_DIR/mnt"
  mkdir -p "$MOUNT_ROOT"

  printf '{"disk":"/dev/sdz"}' >"$CONFIG_FILE"

  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=../../lib/config/accessors.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/accessors.sh"
  # shellcheck source=../../lib/zfs-pools.sh
  source "$BATS_TEST_DIRNAME/../../lib/zfs-pools.sh"
  # shellcheck source=../../lib/layout/single.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/single.sh"
  _LAYOUT_PHASE=1  # simulate validate phase having run


  # Quiet output; error still aborts.
  info()    { :; }
  warn()    { :; }
  section() { :; }
  confirm() { :; }

  # External command stubs.
  blockdev()  { echo $((40 * 1024 * 1024 * 1024)); }
  wipefs()    { printf 'wipefs %s\n'    "$*" >>"$CALLS"; }
  sgdisk()    { printf 'sgdisk %s\n'    "$*" >>"$CALLS"; }
  partprobe() { printf 'partprobe %s\n' "$*" >>"$CALLS"; }
  sleep()     { :; }
  mkfs.fat()  { printf 'mkfs.fat %s\n'  "$*" >>"$CALLS"; }
  mount()     { printf 'mount %s\n'     "$*" >>"$CALLS"; }
  part_name() { printf '%s%s' "$1" "$2"; }

  # zfs-pools.sh seams.
  build_enc_opts()      { :; }
  _zpool_create()       { printf '_zpool_create %s\n'       "$*" >>"$CALLS"; }
  _create_os_datasets() { printf '_create_os_datasets %s\n' "$*" >>"$CALLS"; }
  zfs()                 { printf 'zfs %s\n'                 "$*" >>"$CALLS"; }
  zpool()               { printf 'zpool %s\n'               "$*" >>"$CALLS"; }
  ram_gib()             { echo 4; }

  # Stand-in for calculate_single_disk_layout: populates the two pieces of
  # internal state that downstream seams need, without requiring a real block
  # device. Tests that exercise the real sizing math redefine it inline.
  calculate_single_disk_layout() {
    _LAYOUT_IMPL_DISK="$(cfg '.disk' 'disk')"
    _LAYOUT_IMPL_OS_SECTORS=$((30 * 1024 * 1024 * 2)) # ~30 GiB
  }
}

teardown() { rm -rf "$TEST_DIR"; }

write_config() { printf '%s' "$1" >"$CONFIG_FILE"; }

# ── layout_plan: contract publication ───────────────────────────────────────

@test "layout_plan: publishes LAYOUT_OS_POOL_NAME=rpool by default" {
  layout_plan
  [ "$LAYOUT_OS_POOL_NAME" = "rpool" ]
}

@test "layout_plan: publishes LAYOUT_DATA_POOL_NAMES=(dpool) by default" {
  layout_plan
  [ "${LAYOUT_DATA_POOL_NAMES[0]}" = "dpool" ]
  [ "${#LAYOUT_DATA_POOL_NAMES[@]}" -eq 1 ]
}

@test "layout_plan: LAYOUT_OS_POOL_NAME reflects .os_pool_name config" {
  write_config '{"disk":"/dev/sdz","os_pool_name":"tank"}'
  layout_plan
  [ "$LAYOUT_OS_POOL_NAME" = "tank" ]
}

@test "layout_plan: LAYOUT_DATA_POOL_NAMES reflects .storage_pool_name" {
  write_config '{"disk":"/dev/sdz","storage_pool_name":"vault"}'
  layout_plan
  [ "${LAYOUT_DATA_POOL_NAMES[0]}" = "vault" ]
}

# ── calculate_single_disk_layout: input validation ──────────────────────────

@test "calculate_single_disk_layout: errors when .disk is not a block dev" {
  write_config '{"disk":"/tmp/not-a-real-disk-xyz"}'
  unset -f calculate_single_disk_layout
  # shellcheck source=../../lib/layout/single.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/single.sh"
  run calculate_single_disk_layout
  [ "$status" -ne 0 ]
  [[ "$output" == *"Disk not found"* ]]
}

# ── layout_partition: partitioning + ESP contract ───────────────────────────

@test "layout_partition: sgdisk creates 3 partitions on the disk" {
  layout_plan
  layout_partition
  [ "$(grep -c '^sgdisk -n[123]' "$CALLS")" -eq 3 ]
}

@test "layout_partition: wipefs runs before sgdisk" {
  layout_plan
  layout_partition
  local wipe_line sgdisk_line
  wipe_line="$(grep -n '^wipefs' "$CALLS" | head -1 | cut -d: -f1)"
  sgdisk_line="$(grep -n '^sgdisk' "$CALLS" | head -1 | cut -d: -f1)"
  ((wipe_line < sgdisk_line))
}

@test "layout_partition: ESP partition formatted with mkfs.fat -F32" {
  layout_plan
  layout_partition
  grep -qE '^mkfs.fat -F32 -n EFI /dev/sdz1$' "$CALLS"
}

@test "layout_partition: LAYOUT_ESP_PARTS[0] is the ESP device path" {
  layout_plan
  layout_partition
  [ "${LAYOUT_ESP_PARTS[0]}" = "/dev/sdz1" ]
}

# ── layout_create_pools: zfs pool creation ──────────────────────────────────

@test "layout_create_pools: creates OS pool with LAYOUT_OS_POOL_NAME" {
  layout_plan
  layout_partition
  layout_create_pools
  grep -qE "^_zpool_create ${LAYOUT_OS_POOL_NAME} 12 /dev/sdz2$" "$CALLS"
}

@test "layout_create_pools: creates data pool named in LAYOUT_DATA_POOL_NAMES" {
  layout_plan
  layout_partition
  layout_create_pools
  grep -qE "^_zpool_create ${LAYOUT_DATA_POOL_NAMES[0]} 12 /dev/sdz3$" "$CALLS"
}

@test "layout_create_pools: creates dpool/storage dataset at configured mount" {
  write_config '{"disk":"/dev/sdz","storage_mount":"/srv/data"}'
  layout_plan
  layout_partition
  layout_create_pools
  grep -qE '^zfs create -o mountpoint=/srv/data dpool/storage$' "$CALLS"
}

# ── layout_mount_esp: mount path ────────────────────────────────────────────

@test "layout_mount_esp: mounts ESP at MOUNT_ROOT/boot/efi" {
  layout_plan
  layout_partition
  _LAYOUT_PHASE=4  # skip layout_create_pools; isolate mount_esp behaviour
  layout_mount_esp
  grep -qE "^mount /dev/sdz1 ${MOUNT_ROOT}/boot/efi$" "$CALLS"
}

# ── phase lifecycle smoke (ADR 0016) ────────────────────────────────────────

@test "phase lifecycle: full chain leaves _LAYOUT_PHASE=5" {
  layout_plan
  layout_partition
  layout_create_pools
  layout_mount_esp
  [ "$_LAYOUT_PHASE" -eq 5 ]
}

@test "phase lifecycle: layout_partition before layout_plan errors" {
  run layout_partition
  [ "$status" -ne 0 ]
  [[ "$output" == *"out of order"* ]]
}

# ── layout_validate (ADR 0014) ──────────────────────────────────────────────

@test "layout_validate: errors when .disk is not a block device" {
  _LAYOUT_PHASE=0
  write_config '{"disk":"/tmp/not-a-real-disk-xyz"}'
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"Single disk not found"* ]]
}
