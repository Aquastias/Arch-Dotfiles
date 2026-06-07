#!/usr/bin/env bats
# Tests for .os/lib/layout/multi.sh — pure topology suggestion functions.
# suggest_os_topologies and suggest_storage_topologies have no system calls.

setup() {
  TEST_DIR="$(mktemp -d)"
  CONFIG_FILE="$TEST_DIR/install.json"
  export CONFIG_FILE
  printf '{}' > "$CONFIG_FILE"
  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=../../lib/zfs/pools.sh
  source "$BATS_TEST_DIRNAME/../../lib/zfs/pools.sh"
  # shellcheck source=../../lib/config/accessors.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/accessors.sh"
  # shellcheck source=../../lib/zfs/pool-owners.sh
  source "$BATS_TEST_DIRNAME/../../lib/zfs/pool-owners.sh"
  # shellcheck source=../../lib/layout/multi.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/multi.sh"
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

  # shellcheck source=../../lib/config/accessors.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/accessors.sh"

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

# ── layout_plan: normalized record (pure, no partitioning) ───────────────────

@test "layout_plan: emits ESP per OS disk, primary at index 0 (mirror)" {
  setup_phase_smoke_fixture
  layout_plan
  [ "${#LAYOUT_ESP_PARTS[@]}" -eq 2 ]
  [ "${LAYOUT_ESP_PARTS[0]}" = "/dev/sdx1" ]
  [ "${LAYOUT_ESP_PARTS[1]}" = "/dev/sdy1" ]
}

@test "layout_plan: publishes LAYOUT_OS_POOL_NAME from os_pool.pool_name" {
  setup_phase_smoke_fixture
  layout_plan
  [ "$LAYOUT_OS_POOL_NAME" = "rpool" ]
}

@test "layout_plan: LAYOUT_DATA_POOL_NAMES empty with no storage/data pools" {
  setup_phase_smoke_fixture
  layout_plan
  [ "${#LAYOUT_DATA_POOL_NAMES[@]}" -eq 0 ]
}

# ── resolve_data_pools size warning (issue 04) ───────────────────────────────
# Drives the plan step with a stubbed lsblk (so no real disks needed) and a
# warn() that echoes to stdout, then asserts on the captured $output.

setup_data_pool_size_fixture() {
  # shellcheck source=../../lib/config/accessors.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/accessors.sh"
  section() { :; }
  info()    { :; }
  warn()    { echo "WARN: $*"; }
  # lsblk -bdno SIZE <disk> → bytes; lsblk -dno SIZE <disk> → human.
  lsblk() {
    local disk="${!#}" human bytes
    case "$disk" in
    *da) human="100G"; bytes="$((100 * 1024 * 1024 * 1024))" ;;
    *db) human="200G"; bytes="$((200 * 1024 * 1024 * 1024))" ;;
    *dc) human="100G"; bytes="$((100 * 1024 * 1024 * 1024))" ;;
    *)   human="?";    bytes="0" ;;
    esac
    if [[ "$*" == *-b* ]]; then printf '%s\n' "$bytes"
    else printf '%s\n' "$human"; fi
  }
}

@test "resolve_data_pools: warns on unequal-size mirror pool" {
  setup_data_pool_size_fixture
  write_multi_config '{
    "os_pool":{"pool_name":"rpool","disks":["/dev/osd"]},
    "storage_groups":[],
    "data_pools":[{"name":"tank","topology":"mirror",
                   "disks":["/dev/da","/dev/db"]}]
  }'
  run resolve_data_pools
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN:"* ]]
  [[ "$output" == *"tank"* ]]
  [[ "$output" == *"100G"* ]]
}

@test "resolve_data_pools: silent on equal-size mirror pool" {
  setup_data_pool_size_fixture
  write_multi_config '{
    "os_pool":{"pool_name":"rpool","disks":["/dev/osd"]},
    "storage_groups":[],
    "data_pools":[{"name":"tank","topology":"mirror",
                   "disks":["/dev/da","/dev/dc"]}]
  }'
  run resolve_data_pools
  [ "$status" -eq 0 ]
  [[ "$output" != *"WARN:"* ]]
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

# ── layout_validate: owners validation (pool-owners, ADR 0031) ───────────────

@test "layout_validate: data pool owner not a declared user aborts" {
  _LAYOUT_PHASE=0
  _layout_disk_exists() { return 0; }
  _layout_declared_users() { echo "alice bob"; }
  local osd
  osd="$(_find_block_device)" || skip "no usable block device available"
  write_multi_config "{
    \"os_pool\":{\"disks\":[\"${osd}\"]},
    \"storage_groups\":[],
    \"data_pools\":[{\"name\":\"tank\",\"topology\":\"stripe\",
                     \"disks\":[\"/dev/x1\"],\"owners\":[\"carol\"]}]
  }"
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"Data pool 'tank'"* ]]
  [[ "$output" == *"carol"* ]]
}

@test "layout_validate: data pool owner that is a declared user passes" {
  _LAYOUT_PHASE=0
  _layout_disk_exists() { return 0; }
  _layout_declared_users() { echo "alice bob"; }
  local osd
  osd="$(_find_block_device)" || skip "no usable block device available"
  write_multi_config "{
    \"os_pool\":{\"disks\":[\"${osd}\"]},
    \"storage_groups\":[],
    \"data_pools\":[{\"name\":\"tank\",\"topology\":\"stripe\",
                     \"disks\":[\"/dev/x1\"],\"owners\":[\"bob\"]}]
  }"
  run layout_validate
  [ "$status" -eq 0 ]
}

@test "layout_validate: data pool @group with no members aborts" {
  _LAYOUT_PHASE=0
  _layout_disk_exists() { return 0; }
  _layout_declared_users() { echo "alice" ; }
  _layout_group_map() { printf '' ; }     # no group has any members
  local osd
  osd="$(_find_block_device)" || skip "no usable block device available"
  write_multi_config "{
    \"os_pool\":{\"disks\":[\"${osd}\"]},
    \"storage_groups\":[],
    \"data_pools\":[{\"name\":\"tank\",\"topology\":\"stripe\",
                     \"disks\":[\"/dev/x1\"],\"owners\":[\"@ghosts\"]}]
  }"
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"ghosts"* ]]
}

@test "layout_validate: data pool @group with members passes" {
  _LAYOUT_PHASE=0
  _layout_disk_exists() { return 0; }
  _layout_declared_users() { echo "alice bob" ; }
  _layout_group_map() { printf 'family:alice,bob' ; }
  local osd
  osd="$(_find_block_device)" || skip "no usable block device available"
  write_multi_config "{
    \"os_pool\":{\"disks\":[\"${osd}\"]},
    \"storage_groups\":[],
    \"data_pools\":[{\"name\":\"tank\",\"topology\":\"stripe\",
                     \"disks\":[\"/dev/x1\"],\"owners\":[\"@family\"]}]
  }"
  run layout_validate
  [ "$status" -eq 0 ]
}

@test "layout_validate: storage group owner not a declared user aborts" {
  _LAYOUT_PHASE=0
  _layout_disk_exists() { return 0; }
  _layout_declared_users() { echo "alice" ; }
  local osd
  osd="$(_find_block_device)" || skip "no usable block device available"
  write_multi_config "{
    \"os_pool\":{\"disks\":[\"${osd}\"]},
    \"storage_groups\":[{\"name\":\"media\",\"disks\":[\"/dev/x1\"],
                         \"mount\":\"/data/media\",\"owners\":[\"dave\"]}]
  }"
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"Storage group 'media'"* ]]
  [[ "$output" == *"dave"* ]]
}

@test "layout_validate: valid data pools pass (mirror x2, stripe x1)" {
  _LAYOUT_PHASE=0
  _layout_disk_exists() { return 0; }  # fake data-pool disks "exist"
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
# NB: skip on a missing block device must run in the test body — `skip` inside
# a `$(...)` command substitution only exits the subshell, so the test would
# proceed with an empty osd and fail. Use `osd="$(_find_block_device)" || skip`.

@test "layout_validate: invalid data pool name aborts" {
  _LAYOUT_PHASE=0
  local osd; osd="$(_find_block_device)" || skip "no usable block device available"
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
  local osd; osd="$(_find_block_device)" || skip "no usable block device available"
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
  local osd; osd="$(_find_block_device)" || skip "no usable block device available"
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
  local osd; osd="$(_find_block_device)" || skip "no usable block device available"
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
  local osd; osd="$(_find_block_device)" || skip "no usable block device available"
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
  local osd; osd="$(_find_block_device)" || skip "no usable block device available"
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
  local osd; osd="$(_find_block_device)" || skip "no usable block device available"
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

@test "layout_validate: data pool disk that does not exist aborts" {
  _LAYOUT_PHASE=0
  local osd; osd="$(_find_block_device)" || skip "no usable block device available"
  write_multi_config "{
    \"os_pool\":{\"pool_name\":\"rpool\",\"disks\":[\"${osd}\"]},
    \"storage_groups\":[],
    \"data_pools\":[{\"name\":\"tank\",\"disks\":[\"/tmp/not-a-real-disk\"]}]
  }"
  run layout_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
  [[ "$output" == *"/tmp/not-a-real-disk"* ]]
}

@test "layout_validate: nested data pool mounts are allowed" {
  _LAYOUT_PHASE=0
  _layout_disk_exists() { return 0; }  # fake data-pool disks "exist"
  local osd; osd="$(_find_block_device)" || skip "no usable block device available"
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

# ── issue 05: interactive leftover fold-vs-own-pool ──────────────────────────
# Drives the real plan→partition→pools seam chain with stubbed prompts and
# zpool/zfs, then asserts on the create-path call log — interactively
# synthesized pools must go through the SAME path as declarative data_pools[].

setup_leftover_fixture() {
  CALLS="$TEST_DIR/calls.log"
  export CALLS MOUNT_ROOT="$TEST_DIR/mnt"
  mkdir -p "$MOUNT_ROOT"

  # shellcheck source=../../lib/config/accessors.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/accessors.sh"

  info()    { :; }
  warn()    { :; }
  section() { :; }
  confirm() { :; }
  lsblk()   { echo "?"; }
  sleep()   { :; }
  part_name() { printf '%s%s' "$1" "$2"; }

  wipefs()    { :; }
  sgdisk()    { :; }
  partprobe() { :; }
  mkfs.fat()  { :; }
  mount()     { :; }

  build_enc_opts()      { :; }
  _zpool_create()       { printf '_zpool_create %s\n'       "$*" >>"$CALLS"; }
  _create_os_datasets() { printf '_create_os_datasets %s\n' "$*" >>"$CALLS"; }
  zfs()                 { printf 'zfs %s\n'                 "$*" >>"$CALLS"; }
  zpool()               { printf 'zpool %s\n'               "$*" >>"$CALLS"; }

  # Empty line input → accept the default pool name.
  _read_tty() { printf ''; }

  # pick_option mimic (first word of a chosen option): choose own-pool (2nd
  # option) for any per-disk leftover prompt; option 1 (the OS disk) elsewhere.
  pick_option() {
    local q="$1"; shift
    local idx=0
    [[ "$q" == *"Leftover disk"* ]] && idx=1
    PICK_RESULT="$(echo "${@:$((idx + 1)):1}" | awk '{print $1}')"
  }
}

@test "leftover own-pool: creates a single-disk stripe pool at /data/dataN" {
  setup_leftover_fixture
  _LAYOUT_PHASE=1
  cat >"$CONFIG_FILE" <<'JSONC'
{
  "os_pool": { "pool_name": "rpool", "topology": "none",
               "disks": ["/dev/osd1", "/dev/osd2"] },
  "storage_groups": []
}
JSONC

  layout_plan
  layout_partition
  layout_create_pools

  # A standalone stripe pool 'data1' over the leftover disk's partition…
  grep -q '^_zpool_create data1 12 /dev/osd21$' "$CALLS"
  # …with its data in a child dataset mounted at /data/data1.
  grep -q 'create -o mountpoint=/data/data1 data1/data' "$CALLS"
}

# ── Leftover-Disk Adapter seam (ADR 0034) ────────────────────────────────────
# A non-interactive adapter substitutes for the install-time prompt: the planner
# produces a plan without a TTY and the adapter's choice flows into the record.

@test "leftover seam: non-interactive adapter choice flows into the plan, no TTY" {
  setup_leftover_fixture
  _LAYOUT_PHASE=1
  # Substitute the named Leftover-Disk Adapter (plan.sh) with a non-interactive
  # one: every leftover becomes its own pool with a fixed name.
  layout_leftover_choice()    { LAYOUT_LEFTOVER_CHOICE=own; }
  layout_leftover_pool_name() { LAYOUT_LEFTOVER_POOL_NAME=seamdata; }
  # Prove the planner never falls back to a TTY read for the leftover.
  _read_tty() { echo "TTY READ ATTEMPTED" >&2; return 1; }
  cat >"$CONFIG_FILE" <<'JSONC'
{
  "os_pool": { "pool_name": "rpool", "topology": "none",
               "disks": ["/dev/osd1", "/dev/osd2"] },
  "storage_groups": []
}
JSONC

  layout_plan   # plan only — no partitioning, no destructive ops

  # The adapter's choice (own → 'seamdata') is in the published record.
  printf '%s\n' "${LAYOUT_DATA_POOL_NAMES[@]}" | grep -qx seamdata
}
