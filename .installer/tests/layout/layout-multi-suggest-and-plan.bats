#!/usr/bin/env bats
# Tests: suggestions and plan (split from layout-multi.bats;
# shared setup in layout-multi-helpers.bash)

load layout-multi-helpers


# ── layout_suggest_os_topologies ─────────────────────────────────────────────────────

@test "layout_suggest_os_topologies(1): emits exactly one line" {
  run layout_suggest_os_topologies 1
  [ "$status" -eq 0 ]
  [ "$(awk 'END { print NR }' <<<"$output")" -eq 1 ]
}

@test "layout_suggest_os_topologies(1): the single option is none" {
  run layout_suggest_os_topologies 1
  [ "$status" -eq 0 ]
  [[ "$output" == none* ]]
}

@test "layout_suggest_os_topologies(2): first recommendation is mirror" {
  run layout_suggest_os_topologies 2
  [ "$status" -eq 0 ]
  [[ "${output%%$'\n'*}" == mirror* ]]
}

@test "layout_suggest_os_topologies(3): includes mirror as an option" {
  run layout_suggest_os_topologies 3
  [ "$status" -eq 0 ]
  [[ "$output" == *mirror* ]]
}


# ── layout_suggest_storage_topologies ────────────────────────────────────────────────

@test "layout_suggest_storage_topologies(1): first recommendation is independent" {
  run layout_suggest_storage_topologies 1
  [ "$status" -eq 0 ]
  [[ "${output%%$'\n'*}" == independent* ]]
}

@test "layout_suggest_storage_topologies(2): first recommendation is mirror" {
  run layout_suggest_storage_topologies 2
  [ "$status" -eq 0 ]
  [[ "${output%%$'\n'*}" == mirror* ]]
}

@test "layout_suggest_storage_topologies(3): first recommendation is raidz1" {
  run layout_suggest_storage_topologies 3
  [ "$status" -eq 0 ]
  [[ "${output%%$'\n'*}" == raidz1* ]]
}

@test "layout_suggest_storage_topologies(4): first recommendation is raidz1" {
  run layout_suggest_storage_topologies 4
  [ "$status" -eq 0 ]
  [[ "${output%%$'\n'*}" == raidz1* ]]
}

@test "layout_suggest_storage_topologies(5): first recommendation is raidz2" {
  run layout_suggest_storage_topologies 5
  [ "$status" -eq 0 ]
  [[ "${output%%$'\n'*}" == raidz2* ]]
}

@test "layout_suggest_storage_topologies(6): first recommendation is raidz2" {
  run layout_suggest_storage_topologies 6
  [ "$status" -eq 0 ]
  [[ "${output%%$'\n'*}" == raidz2* ]]
}


# The phase-lifecycle smoke (full chain → _LAYOUT_PHASE=5; out-of-order guard)
# is topology-invariant, so it lives once in layout-single.bats (ADR 0103
# redundancy pass); layout-multi keeps only the mirror-specific assertions.

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


# ── layout_resolve_data_pools size warning (issue 04) ───────────────────────────────

@test "layout_resolve_data_pools: warns on unequal-size mirror pool" {
  setup_data_pool_size_fixture
  write_multi_config '{
    "os_pool":{"pool_name":"rpool","disks":["/dev/osd"]},
    "storage_groups":[],
    "data_pools":[{"name":"tank","topology":"mirror",
                   "disks":["/dev/da","/dev/db"]}]
  }'
  run layout_resolve_data_pools
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN:"* ]]
  [[ "$output" == *"tank"* ]]
  [[ "$output" == *"100G"* ]]
}

@test "layout_resolve_data_pools: silent on equal-size mirror pool" {
  setup_data_pool_size_fixture
  write_multi_config '{
    "os_pool":{"pool_name":"rpool","disks":["/dev/osd"]},
    "storage_groups":[],
    "data_pools":[{"name":"tank","topology":"mirror",
                   "disks":["/dev/da","/dev/dc"]}]
  }'
  run layout_resolve_data_pools
  [ "$status" -eq 0 ]
  [[ "$output" != *"WARN:"* ]]
}


# ── _zfs_multi_validate_mount_is_reserved (pure, issue 03) ──────────────────────────────────────

@test "_zfs_multi_validate_mount_is_reserved: /home is reserved" {
  run _zfs_multi_validate_mount_is_reserved /home
  [ "$status" -eq 0 ]
}

@test "_zfs_multi_validate_mount_is_reserved: / is reserved" {
  run _zfs_multi_validate_mount_is_reserved /
  [ "$status" -eq 0 ]
}

@test "_zfs_multi_validate_mount_is_reserved: /var/log subtree is reserved" {
  run _zfs_multi_validate_mount_is_reserved /var/log
  [ "$status" -eq 0 ]
}

@test "_zfs_multi_validate_mount_is_reserved: /boot/efi subtree is reserved" {
  run _zfs_multi_validate_mount_is_reserved /boot/efi
  [ "$status" -eq 0 ]
}

@test "_zfs_multi_validate_mount_is_reserved: /data is not reserved" {
  run _zfs_multi_validate_mount_is_reserved /data
  [ "$status" -ne 0 ]
}

@test "_zfs_multi_validate_mount_is_reserved: /variable is not reserved (subtree, not prefix)" {
  run _zfs_multi_validate_mount_is_reserved /variable
  [ "$status" -ne 0 ]
}


# ── layout_validate (ADR 0014) ──────────────────────────────────────────────

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
  layout_disk_exists() { return 0; }
  _zfs_multi_validate_declared_users() { echo "alice bob"; }
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
  layout_disk_exists() { return 0; }
  _zfs_multi_validate_declared_users() { echo "alice bob"; }
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
  layout_disk_exists() { return 0; }
  _zfs_multi_validate_declared_users() { echo "alice" ; }
  _zfs_multi_validate_group_map() { printf '' ; }     # no group has any members
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
  layout_disk_exists() { return 0; }
  _zfs_multi_validate_declared_users() { echo "alice bob" ; }
  _zfs_multi_validate_group_map() { printf 'family:alice,bob' ; }
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
  layout_disk_exists() { return 0; }
  _zfs_multi_validate_declared_users() { echo "alice" ; }
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
  layout_disk_exists() { return 0; }  # fake data-pool disks "exist"
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
