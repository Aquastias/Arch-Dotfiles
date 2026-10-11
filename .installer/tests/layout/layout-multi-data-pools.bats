#!/usr/bin/env bats
# Tests: data pools (split from layout-multi.bats;
# shared setup in layout-multi-helpers.bash)

load layout-multi-helpers


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
  layout_disk_exists() { return 0; }  # fake data-pool disks "exist"
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
  grep -q '^zfs_create_pool data1 12 /dev/osd21$' "$CALLS"
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
  _zfs_multi_topology_read_tty() { echo "TTY READ ATTEMPTED" >&2; return 1; }
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
