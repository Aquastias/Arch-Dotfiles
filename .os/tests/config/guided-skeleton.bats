#!/usr/bin/env bats
# Tests for .os/lib/config/skeleton.sh — the Guided Installer's Disk Skeleton
# builder (ADR 0039, issue 04). Pure: a named ZFS shape preset → a device-less
# pool skeleton (mode + os_pool + storage_groups[] / data_pools[] carrying
# topology + disk_count), merged into the Config State and later device-baked by
# the Pre-Install Picker (picker_build_assignment / picker_assign_disks). The
# skeleton's disk_counts agree with the picker min-disk table.
#
# Behaviour under test (external only — the skeleton JSON a preset emits and the
# rule checks over it), never internal structure.

setup() {
  error() { echo "[error] $*" >&2; return 1; }
  export -f error

  # shellcheck source=../../lib/config/skeleton.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/skeleton.sh"
}

# ── tracer: OS mirror + raidz1 storage preset fills a valid skeleton ────────

@test "skeleton_preset: os-mirror-raidz1 fills OS mirror + raidz1 storage" {
  run skeleton_preset os-mirror-raidz1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "multi"'
  echo "$output" | jq -e '.os_pool.topology == "mirror" and .os_pool.disk_count == 2'
  echo "$output" | jq -e '.storage_groups[0].topology == "raidz1"'
  echo "$output" | jq -e '.storage_groups[0].disk_count == 3'
}

@test "skeleton_preset: single is the device-less single-disk shape" {
  run skeleton_preset single
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "single"'
}

@test "skeleton_preset: os-mirror is a 2-disk mirrored OS, no storage" {
  run skeleton_preset os-mirror
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "multi"'
  echo "$output" | jq -e '.os_pool.topology == "mirror" and .os_pool.disk_count == 2'
  echo "$output" | jq -e 'has("storage_groups") | not'
}

@test "skeleton_preset: data-pools is OS none + a standalone data pool" {
  run skeleton_preset data-pools
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.os_pool.topology == "none" and .os_pool.disk_count == 1'
  echo "$output" | jq -e '.data_pools[0].name == "tank"'
  echo "$output" | jq -e '.data_pools[0].disk_count == 1'
}

@test "skeleton_preset: an unknown preset errors" {
  run skeleton_preset bogus
  [ "$status" -ne 0 ]
}

# ── total disks: the flat count the picker must collect (Σ disk_count) ───────

@test "skeleton_total_disks: single needs 1" {
  run skeleton_total_disks "$(skeleton_preset single)"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "skeleton_total_disks: os-mirror-raidz1 needs 5 (2 OS + 3 storage)" {
  run skeleton_total_disks "$(skeleton_preset os-mirror-raidz1)"
  [ "$status" -eq 0 ]
  [ "$output" -eq 5 ]
}

@test "skeleton_total_disks: data-pools needs 2 (1 OS + 1 data)" {
  run skeleton_total_disks "$(skeleton_preset data-pools)"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

# ── validate: disk_counts agree with the picker min-disk table ──────────────

@test "skeleton_validate: every preset is installable" {
  for p in single os-mirror os-mirror-raidz1 data-pools; do
    run skeleton_validate "$(skeleton_preset "$p")"
    [ "$status" -eq 0 ] || { echo "preset $p rejected: $output"; return 1; }
  done
}

@test "skeleton_validate: an under-populated OS pool is named in the error" {
  skel='{"mode":"multi","os_pool":{"topology":"mirror","disk_count":1}}'
  run skeleton_validate "$skel"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "os_pool" ]]
}

@test "skeleton_validate: an under-populated storage group is named" {
  skel='{"mode":"multi","os_pool":{"topology":"mirror","disk_count":2},
    "storage_groups":[{"topology":"raidz1","disk_count":2}]}'
  run skeleton_validate "$skel"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "storage_groups[0]" ]]
}

# ── assignment summary: the per-group confirm screen (skeleton + picked disks)

@test "skeleton_assignment_summary: renders each group's topology + disks" {
  skel="$(skeleton_preset os-mirror-raidz1)"
  a='{"mode":"multi","os_pool":["/dev/a","/dev/b"],
      "storage_groups":[["/dev/c","/dev/d","/dev/e"]]}'
  run skeleton_assignment_summary "$skel" "$a"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "mirror"
  echo "$output" | grep -q "/dev/a"
  echo "$output" | grep -q "/dev/b"
  echo "$output" | grep -q "raidz1"
  echo "$output" | grep -q "/dev/e"
}

@test "skeleton_assignment_summary: names a standalone data pool + its disk" {
  skel="$(skeleton_preset data-pools)"
  a='{"mode":"multi","os_pool":["/dev/a"],"data_pools":[["/dev/b"]]}'
  run skeleton_assignment_summary "$skel" "$a"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "tank"
  echo "$output" | grep -q "/dev/b"
}

# ── composable builders: the Advanced door authors a skeleton group by group ─

@test "skeleton_new_multi: starts a multi skeleton with the OS pool" {
  run skeleton_new_multi mirror 2
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "multi"'
  echo "$output" | jq -e '.os_pool.topology == "mirror" and .os_pool.disk_count == 2'
}

@test "skeleton_add_storage: appends a named storage group" {
  skel="$(skeleton_new_multi mirror 2)"
  run skeleton_add_storage "$skel" data raidz1 3
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.storage_groups[0].name == "data"'
  echo "$output" | jq -e \
    '.storage_groups[0].topology == "raidz1" and .storage_groups[0].disk_count == 3'
}

@test "skeleton_add_storage: owners become an array; two groups keep order" {
  skel="$(skeleton_new_multi mirror 2)"
  skel="$(skeleton_add_storage "$skel" fast mirror 2 "alice @team")"
  run skeleton_add_storage "$skel" bulk raidz1 3
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.storage_groups[0].name == "fast"'
  echo "$output" | jq -e '.storage_groups[0].owners == ["alice","@team"]'
  echo "$output" | jq -e '.storage_groups[1].name == "bulk"'
}

@test "skeleton_add_data_pool: appends a standalone data pool" {
  skel="$(skeleton_new_multi none 1)"
  run skeleton_add_data_pool "$skel" tank stripe 1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.data_pools[0].name == "tank"'
  echo "$output" | jq -e \
    '.data_pools[0].topology == "stripe" and .data_pools[0].disk_count == 1'
}

@test "skeleton builders: an authored skeleton validates + totals its disks" {
  skel="$(skeleton_new_multi mirror 2)"
  skel="$(skeleton_add_storage "$skel" data raidz1 3)"
  run skeleton_validate "$skel"
  [ "$status" -eq 0 ]
  run skeleton_total_disks "$skel"
  [ "$output" -eq 5 ]
}
