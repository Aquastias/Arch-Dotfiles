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
