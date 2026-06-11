#!/usr/bin/env bats
# Tests for .os/lib/picker.sh — disk->group assignment (unified-host-profile
# /02). Pure, libvirt-free: given a profile pool skeleton (os_pool +
# storage_groups + data_pools, NO device fields) and a per-group disk
# assignment, picker_assign_disks computes the effective config (skeleton +
# assigned devices) or fails with a clear min-disk message.
#
# Assignment model (per-group): each declared group is assigned its own
# disks; each group's count is validated against the min-disk table
# (mirror/stripe >=2, raidz1 >=3, raidz2 >=4); single mode resolves exactly
# one OS device.

setup() {
  # shellcheck source=../lib/picker.sh
  source "$BATS_TEST_DIRNAME/../lib/picker.sh"
}

# ── single mode: exactly one OS device ─────────────────────────────────────

@test "picker_assign_disks: single mode writes mode=single + disk, skeleton kept" {
  run picker_assign_disks \
    '{"system":{"hostname":"h"},"os_pool":{"pool_name":"rpool"}}' \
    '{"mode":"single","disk":"/dev/d0"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "single"'
  echo "$output" | jq -e '.disk == "/dev/d0"'
  echo "$output" | jq -e '.system.hostname == "h"'
  echo "$output" | jq -e '.os_pool.pool_name == "rpool"'
  # No host_profile field — the directory name is the identity (ADR 0036).
  echo "$output" | jq -e 'has("host_profile") | not'
}

@test "picker_assign_disks: single mode with two disks fails with a clear message" {
  run picker_assign_disks '{"os_pool":{}}' \
    '{"mode":"single","os_pool":["/dev/d0","/dev/d1"]}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"single"* ]]
}

# ── multi mode: os_pool assignment + min-disk validation ───────────────────

@test "picker_assign_disks: multi os_pool mirror + 2 disks writes os_pool.disks" {
  run picker_assign_disks \
    '{"os_pool":{"pool_name":"rpool","topology":"mirror"}}' \
    '{"mode":"multi","os_pool":["/dev/d0","/dev/d1"]}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "multi"'
  echo "$output" | jq -e '.os_pool.topology == "mirror"'
  echo "$output" | jq -e '.os_pool.disks == ["/dev/d0","/dev/d1"]'
}

@test "picker_assign_disks: under-populated os_pool raidz1 fails naming the group" {
  run picker_assign_disks \
    '{"os_pool":{"topology":"raidz1"}}' \
    '{"mode":"multi","os_pool":["/dev/d0","/dev/d1"]}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"os_pool"* ]]
  [[ "$output" == *"raidz1"* ]]
}

# ── assignment-path min check (ADR 0037): stripe/independent>=1, none/single=1,
#    mirror>=2, raidz1>=3, raidz2>=4 — distinct from picker_validate_layout ───

@test "picker_assign_disks: os_pool none + 1 disk is accepted (ADR 0037)" {
  run picker_assign_disks \
    '{"os_pool":{"pool_name":"rpool","topology":"none"}}' \
    '{"mode":"multi","os_pool":["/dev/d0"]}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.os_pool.topology == "none"'
  echo "$output" | jq -e '.os_pool.disks == ["/dev/d0"]'
}

@test "picker_assign_disks: data_pool stripe + 1 disk is accepted (ADR 0037)" {
  run picker_assign_disks \
    '{"os_pool":{"topology":"mirror"},
      "data_pools":[{"name":"tank0","topology":"stripe"}]}' \
    '{"mode":"multi","os_pool":["/dev/a","/dev/b"],
      "data_pools":[["/dev/c"]]}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.data_pools[0].disks == ["/dev/c"]'
}

@test "picker_assign_disks: storage_group independent + 1 disk is accepted" {
  run picker_assign_disks \
    '{"os_pool":{"topology":"mirror"},
      "storage_groups":[{"name":"g","topology":"independent"}]}' \
    '{"mode":"multi","os_pool":["/dev/a","/dev/b"],
      "storage_groups":[["/dev/c"]]}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.storage_groups[0].disks == ["/dev/c"]'
}

# ── multi mode: storage_groups + data_pools per-group assignment ───────────

@test "picker_assign_disks: storage_group raidz1 + 3 disks writes its disks" {
  run picker_assign_disks \
    '{"os_pool":{"topology":"mirror"},
      "storage_groups":[{"name":"data","topology":"raidz1"}]}' \
    '{"mode":"multi","os_pool":["/dev/a","/dev/b"],
      "storage_groups":[["/dev/c","/dev/d","/dev/e"]]}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.storage_groups[0].name == "data"'
  echo "$output" | jq -e '.storage_groups[0].disks == ["/dev/c","/dev/d","/dev/e"]'
}

@test "picker_assign_disks: under-populated storage_group raidz1 fails naming it" {
  run picker_assign_disks \
    '{"os_pool":{"topology":"mirror"},
      "storage_groups":[{"name":"data","topology":"raidz1"}]}' \
    '{"mode":"multi","os_pool":["/dev/a","/dev/b"],
      "storage_groups":[["/dev/c","/dev/d"]]}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"storage_groups"* ]]
  [[ "$output" == *"raidz1"* ]]
}

@test "picker_assign_disks: data_pool mirror + 2 disks writes its disks" {
  run picker_assign_disks \
    '{"os_pool":{"topology":"mirror"},
      "data_pools":[{"name":"tank","topology":"mirror"}]}' \
    '{"mode":"multi","os_pool":["/dev/a","/dev/b"],
      "data_pools":[["/dev/c","/dev/d"]]}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.data_pools[0].name == "tank"'
  echo "$output" | jq -e '.data_pools[0].disks == ["/dev/c","/dev/d"]'
}

# ── picker_build_assignment: slice a flat picked-disk list onto groups by
#    disk_count, in declared order (os_pool → storage_groups[] → data_pools[]) ─

@test "picker_build_assignment: slices disks per disk_count in declared order" {
  run picker_build_assignment \
    '{"mode":"multi",
      "os_pool":{"topology":"none","disk_count":1},
      "storage_groups":[{"name":"g","topology":"raidz1","disk_count":3}],
      "data_pools":[{"name":"t","topology":"mirror","disk_count":2}]}' \
    /dev/a /dev/b /dev/c /dev/d /dev/e /dev/f
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "multi"'
  echo "$output" | jq -e '.os_pool == ["/dev/a"]'
  echo "$output" | jq -e '.storage_groups == [["/dev/b","/dev/c","/dev/d"]]'
  echo "$output" | jq -e '.data_pools == [["/dev/e","/dev/f"]]'
}

@test "picker_build_assignment: wrong total aborts naming the expected count" {
  run picker_build_assignment \
    '{"mode":"multi",
      "os_pool":{"topology":"none","disk_count":1},
      "data_pools":[{"name":"t","topology":"mirror","disk_count":2}]}' \
    /dev/a /dev/b
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected 3"* ]]
  [[ "$output" == *"got 2"* ]]
}

@test "picker_build_assignment: os_pool none/single defaults disk_count to 1" {
  run picker_build_assignment \
    '{"mode":"multi","os_pool":{"topology":"none"}}' /dev/a
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.os_pool == ["/dev/a"]'
}

@test "picker_build_assignment: a non-os group missing disk_count aborts" {
  run picker_build_assignment \
    '{"mode":"multi","os_pool":{"topology":"none","disk_count":1},
      "data_pools":[{"name":"t","topology":"mirror"}]}' \
    /dev/a /dev/b /dev/c
  [ "$status" -ne 0 ]
  [[ "$output" == *"data_pools[0]"* ]]
}

@test "picker_build_assignment: output feeds picker_assign_disks end-to-end" {
  local profile='{"system":{"hostname":"nas"},
    "os_pool":{"pool_name":"rpool","topology":"none","disk_count":1},
    "data_pools":[{"name":"tank0","topology":"stripe","disk_count":1},
                  {"name":"tank1","topology":"mirror","disk_count":2}]}'
  local asg
  asg="$(picker_build_assignment "$profile" /dev/a /dev/b /dev/c /dev/d)"
  run picker_assign_disks "$profile" "$asg"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.os_pool.disks == ["/dev/a"]'
  echo "$output" | jq -e '.data_pools[0].disks == ["/dev/b"]'
  echo "$output" | jq -e '.data_pools[1].disks == ["/dev/c","/dev/d"]'
}

@test "picker_assign_disks: full multi-group assembly fills every group's disks" {
  run picker_assign_disks \
    '{"system":{"hostname":"nas"},
      "os_pool":{"pool_name":"rpool","topology":"mirror","ashift":13},
      "storage_groups":[{"name":"bulk","topology":"raidz1","owners":["a"]}],
      "data_pools":[{"name":"scratch","topology":"stripe"}]}' \
    '{"mode":"multi",
      "os_pool":["/dev/a","/dev/b"],
      "storage_groups":[["/dev/c","/dev/d","/dev/e"]],
      "data_pools":[["/dev/f","/dev/g"]]}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "multi"'
  echo "$output" | jq -e '.os_pool.disks == ["/dev/a","/dev/b"]'
  echo "$output" | jq -e '.os_pool.ashift == 13'
  echo "$output" | jq -e '.storage_groups[0].disks == ["/dev/c","/dev/d","/dev/e"]'
  echo "$output" | jq -e '.storage_groups[0].owners == ["a"]'
  echo "$output" | jq -e '.data_pools[0].disks == ["/dev/f","/dev/g"]'
  echo "$output" | jq -e '.system.hostname == "nas"'
}
