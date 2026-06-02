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
  _LAYOUT_PHASE=1  # simulate validate phase having run
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

# ── _mount_is_reserved (pure, issue 03) ──────────────────────────────────────

@test "_mount_is_reserved: /home is reserved" {
  run _mount_is_reserved /home
  [ "$status" -eq 0 ]
}

@test "_mount_is_reserved: / is reserved" {
  run _mount_is_reserved /
  [ "$status" -eq 0 ]
}

@test "_mount_is_reserved: /var/log subtree is reserved" {
  run _mount_is_reserved /var/log
  [ "$status" -eq 0 ]
}

@test "_mount_is_reserved: /boot/efi subtree is reserved" {
  run _mount_is_reserved /boot/efi
  [ "$status" -eq 0 ]
}

@test "_mount_is_reserved: /data is not reserved" {
  run _mount_is_reserved /data
  [ "$status" -ne 0 ]
}

@test "_mount_is_reserved: /variable is not reserved (subtree, not prefix)" {
  run _mount_is_reserved /variable
  [ "$status" -ne 0 ]
}

# ── layout_validate (ADR 0014) ──────────────────────────────────────────────

write_multi_config() { printf '%s' "$1" >"$CONFIG_FILE"; }

_find_block_device() {
  local d
  for d in /dev/loop0 /dev/loop1 /dev/sda /dev/nvme0n1 /dev/vda /dev/ram0; do
    [[ -b "$d" ]] && { printf %s "$d"; return; }
  done
  return 1
}

@test "layout_validate: errors on bad os_pool.topology value" {
  _LAYOUT_PHASE=0
  write_multi_config '{
    "os_pool":{"topology":"bogus","disks":["/dev/sdz"]},
    "storage_groups":[]
  }'
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"os_pool.topology must be mirror|stripe|none"* ]]
}

@test "layout_validate: errors when os_pool.disks is empty" {
  _LAYOUT_PHASE=0
  write_multi_config '{
    "os_pool":{"disks":[]},
    "storage_groups":[]
  }'
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"os_pool.disks must list at least 1 disk"* ]]
}

@test "layout_validate: errors when OS disk is not a block device" {
  _LAYOUT_PHASE=0
  write_multi_config '{
    "os_pool":{"disks":["/tmp/not-a-real-disk-xyz"]},
    "storage_groups":[]
  }'
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"OS disk not found: /tmp/not-a-real-disk-xyz"* ]]
}

@test "layout_validate: errors when storage group has no disks" {
  _LAYOUT_PHASE=0
  local osd
  osd="$(_find_block_device)" || skip "no usable block device available"
  write_multi_config "{
    \"os_pool\":{\"disks\":[\"${osd}\"]},
    \"storage_groups\":[{\"name\":\"empty\",\"disks\":[]}]
  }"
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"Storage group 'empty' has no disks"* ]]
}

@test "layout_validate: errors when storage group disk missing" {
  _LAYOUT_PHASE=0
  local osd
  osd="$(_find_block_device)" || skip "no usable block device available"
  write_multi_config "{
    \"os_pool\":{\"disks\":[\"${osd}\"]},
    \"storage_groups\":[{\"name\":\"data\",\"disks\":[\"/tmp/not-real\"]}]
  }"
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"Group 'data' disk not found: /tmp/not-real"* ]]
}

# ── layout_validate: data_pools[] topology rules (ADR 0027, issue 02) ────────

@test "layout_validate: data pool mirror with one disk aborts" {
  _LAYOUT_PHASE=0
  local osd
  osd="$(_find_block_device)" || skip "no usable block device available"
  write_multi_config "{
    \"os_pool\":{\"disks\":[\"${osd}\"]},
    \"storage_groups\":[],
    \"data_pools\":[{\"name\":\"tank\",\"topology\":\"mirror\",
                     \"disks\":[\"/dev/x1\"]}]
  }"
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"Data pool 'tank'"* ]]
  [[ "$output" == *"mirror"* ]]
  [[ "$output" == *"at least 2"* ]]
}

@test "layout_validate: data pool raidz2 with two disks aborts" {
  _LAYOUT_PHASE=0
  local osd
  osd="$(_find_block_device)" || skip "no usable block device available"
  write_multi_config "{
    \"os_pool\":{\"disks\":[\"${osd}\"]},
    \"storage_groups\":[],
    \"data_pools\":[{\"name\":\"vault\",\"topology\":\"raidz2\",
                     \"disks\":[\"/dev/x1\",\"/dev/x2\"]}]
  }"
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"Data pool 'vault'"* ]]
  [[ "$output" == *"at least 3"* ]]
}

@test "layout_validate: data pool topology none aborts with guidance" {
  _LAYOUT_PHASE=0
  local osd
  osd="$(_find_block_device)" || skip "no usable block device available"
  write_multi_config "{
    \"os_pool\":{\"disks\":[\"${osd}\"]},
    \"storage_groups\":[],
    \"data_pools\":[{\"name\":\"tank\",\"topology\":\"none\",
                     \"disks\":[\"/dev/x1\",\"/dev/x2\"]}]
  }"
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"Data pool 'tank'"* ]]
  [[ "$output" == *"stripe"* ]]
  [[ "$output" == *"data_pools[]"* ]]
}

@test "layout_validate: data pool topology independent aborts" {
  _LAYOUT_PHASE=0
  local osd
  osd="$(_find_block_device)" || skip "no usable block device available"
  write_multi_config "{
    \"os_pool\":{\"disks\":[\"${osd}\"]},
    \"storage_groups\":[],
    \"data_pools\":[{\"name\":\"tank\",\"topology\":\"independent\",
                     \"disks\":[\"/dev/x1\",\"/dev/x2\"]}]
  }"
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"independent"* ]]
}

@test "layout_validate: valid data pools pass (mirror x2, stripe x1)" {
  _LAYOUT_PHASE=0
  local osd
  osd="$(_find_block_device)" || skip "no usable block device available"
  write_multi_config "{
    \"os_pool\":{\"disks\":[\"${osd}\"]},
    \"storage_groups\":[],
    \"data_pools\":[
      {\"name\":\"mir\",\"topology\":\"mirror\",
       \"disks\":[\"/dev/x1\",\"/dev/x2\"]},
      {\"name\":\"solo\",\"disks\":[\"/dev/x3\"]}
    ]
  }"
  run layout_validate
  [ "$status" -eq 0 ]
}

# ── layout_validate: data_pools[] name/uniqueness/mount (issue 03) ───────────

_os_disk_or_skip() { _find_block_device || skip "no usable block device"; }

@test "layout_validate: invalid data pool name aborts" {
  _LAYOUT_PHASE=0
  local osd; osd="$(_os_disk_or_skip)"
  write_multi_config "{
    \"os_pool\":{\"pool_name\":\"rpool\",\"disks\":[\"${osd}\"]},
    \"storage_groups\":[],
    \"data_pools\":[{\"name\":\"raidz1\",\"disks\":[\"/dev/x1\"]}]
  }"
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"raidz1"* ]]
  [[ "$output" == *"reserved"* ]]
}

@test "layout_validate: duplicate data pool name aborts" {
  _LAYOUT_PHASE=0
  local osd; osd="$(_os_disk_or_skip)"
  write_multi_config "{
    \"os_pool\":{\"pool_name\":\"rpool\",\"disks\":[\"${osd}\"]},
    \"storage_groups\":[],
    \"data_pools\":[
      {\"name\":\"tank\",\"disks\":[\"/dev/x1\"]},
      {\"name\":\"tank\",\"disks\":[\"/dev/x2\"]}
    ]
  }"
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"tank"* ]]
}

@test "layout_validate: data pool name colliding with rpool aborts" {
  _LAYOUT_PHASE=0
  local osd; osd="$(_os_disk_or_skip)"
  write_multi_config "{
    \"os_pool\":{\"pool_name\":\"rpool\",\"disks\":[\"${osd}\"]},
    \"storage_groups\":[],
    \"data_pools\":[{\"name\":\"rpool\",\"disks\":[\"/dev/x1\"]}]
  }"
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"rpool"* ]]
}

@test "layout_validate: disk reused between OS pool and data pool aborts" {
  _LAYOUT_PHASE=0
  local osd; osd="$(_os_disk_or_skip)"
  write_multi_config "{
    \"os_pool\":{\"pool_name\":\"rpool\",\"disks\":[\"${osd}\"]},
    \"storage_groups\":[],
    \"data_pools\":[{\"name\":\"tank\",\"disks\":[\"${osd}\"]}]
  }"
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"${osd}"* ]]
}

@test "layout_validate: disk reused across two data pools aborts" {
  _LAYOUT_PHASE=0
  local osd; osd="$(_os_disk_or_skip)"
  write_multi_config "{
    \"os_pool\":{\"pool_name\":\"rpool\",\"disks\":[\"${osd}\"]},
    \"storage_groups\":[],
    \"data_pools\":[
      {\"name\":\"a\",\"disks\":[\"/dev/x1\"]},
      {\"name\":\"b\",\"disks\":[\"/dev/x1\"]}
    ]
  }"
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"/dev/x1"* ]]
}

@test "layout_validate: data pool mount on reserved path aborts" {
  _LAYOUT_PHASE=0
  local osd; osd="$(_os_disk_or_skip)"
  write_multi_config "{
    \"os_pool\":{\"pool_name\":\"rpool\",\"disks\":[\"${osd}\"]},
    \"storage_groups\":[],
    \"data_pools\":[{\"name\":\"tank\",\"mount\":\"/home\",
                     \"disks\":[\"/dev/x1\"]}]
  }"
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"/home"* ]]
}

@test "layout_validate: two pools sharing a mountpoint aborts" {
  _LAYOUT_PHASE=0
  local osd; osd="$(_os_disk_or_skip)"
  write_multi_config "{
    \"os_pool\":{\"pool_name\":\"rpool\",\"disks\":[\"${osd}\"]},
    \"storage_groups\":[],
    \"data_pools\":[
      {\"name\":\"a\",\"mount\":\"/data/shared\",\"disks\":[\"/dev/x1\"]},
      {\"name\":\"b\",\"mount\":\"/data/shared\",\"disks\":[\"/dev/x2\"]}
    ]
  }"
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"/data/shared"* ]]
}

@test "layout_validate: nested data pool mounts are allowed" {
  _LAYOUT_PHASE=0
  local osd; osd="$(_os_disk_or_skip)"
  write_multi_config "{
    \"os_pool\":{\"pool_name\":\"rpool\",\"disks\":[\"${osd}\"]},
    \"storage_groups\":[],
    \"data_pools\":[
      {\"name\":\"a\",\"mount\":\"/data\",\"disks\":[\"/dev/x1\"]},
      {\"name\":\"b\",\"mount\":\"/data/tank0\",\"disks\":[\"/dev/x2\"]}
    ]
  }"
  run layout_validate
  [ "$status" -eq 0 ]
}
