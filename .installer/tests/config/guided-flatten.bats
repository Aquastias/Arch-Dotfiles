#!/usr/bin/env bats
# Tests for the flatten + device-aware assignment builders — issue 04. In-Menu
# Disk Binding leaves per-group devices[] (+ a single-disk root_disk) in the
# in-session skeleton; these pure builders flatten it back to a device-less
# profile (Save) and lift it into the per-group assignment JSON
# (Proceed/Export). Pure: JSON in, JSON out. No fzf, no disks.

load ../lib/json-helpers

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/config/skeleton.sh"
}

# ── skeleton_flatten_devices (AC1) ───────────────────────────────────────────

@test "skeleton_flatten_devices: derives count, drops devices + root_disk" {
  local skeleton='{"mode":"multi","root_disk":"/dev/x",
    "os_pool":{"pool_name":"rpool","topology":"mirror",
               "devices":["/d/a","/d/b"],"disk_count":2},
    "data_pools":[{"name":"tank0","topology":"single",
                   "devices":["/d/c"],"disk_count":1}]}'
  run skeleton_flatten_devices "$skeleton"
  output_satisfies '.os_pool.disk_count == 2'
  output_satisfies '(.os_pool | has("devices")) == false'
  output_satisfies '.data_pools[0].disk_count == 1'
  output_satisfies '(has("root_disk")) == false'
}

@test "skeleton_flatten_devices: a device-less group is untouched" {
  local skeleton='{"data_pools":[{"name":"t","topology":"mirror","disk_count":2}]}'
  run skeleton_flatten_devices "$skeleton"
  output_satisfies '.data_pools[0].disk_count == 2'
  output_satisfies '(.data_pools[0] | has("devices")) == false'
}

# ── skeleton_any_bound / skeleton_counted_disks ──────────────────────────────

@test "skeleton_any_bound: true when a group has a devices key" {
  skeleton_any_bound '{"os_pool":{"devices":["/d/a"]}}'
  local counted='{"os_pool":{"disk_count":2},"data_pools":[{"disk_count":1}]}'
  ! skeleton_any_bound "$counted"
}

@test "skeleton_counted_disks: sums disk_count over device-less groups only" {
  local skeleton='{"os_pool":{"devices":["/d/a","/d/b"],"disk_count":2},
    "data_pools":[{"disk_count":3},{"devices":["/d/c"],"disk_count":1}]}'
  [ "$(skeleton_counted_disks "$skeleton")" = "3" ]
}

# ── skeleton_build_assignment (AC2, AC4) ─────────────────────────────────────

@test "skeleton_build_assignment: fully bound needs no disks, uses devices" {
  local skeleton='{"os_pool":{"topology":"mirror","devices":["/d/a","/d/b"]},
    "data_pools":[{"topology":"single","devices":["/d/c"]}]}'
  run skeleton_build_assignment "$skeleton"
  output_satisfies '.os_pool == ["/d/a","/d/b"]'
  output_satisfies '.data_pools[0] == ["/d/c"]'
}

@test "skeleton_build_assignment: mixed — bound uses devices, counted slices" {
  local skeleton='{"os_pool":{"topology":"mirror","devices":["/d/a","/d/b"]},
    "data_pools":[{"topology":"stripe","disk_count":2}]}'
  run skeleton_build_assignment "$skeleton" /d/x /d/y
  output_satisfies '.os_pool == ["/d/a","/d/b"]'
  output_satisfies '.data_pools[0] == ["/d/x","/d/y"]'
}

@test "skeleton_build_assignment: too few disks for the counted groups aborts" {
  local skeleton='{"os_pool":{"topology":"mirror","disk_count":2}}'
  run skeleton_build_assignment "$skeleton" /d/x
  [ "$status" -ne 0 ]
}

# ── AC3: devices-built assignment ≡ picker_build_assignment ──────────────────

@test "fully-bound assignment equals picker_build_assignment for same disks" {
  local skeleton='{"os_pool":{"topology":"mirror","devices":["/d/a","/d/b"]},
    "storage_groups":[{"name":"data","topology":"raidz1",
                       "devices":["/d/c","/d/d","/d/e"]}],
    "data_pools":[{"name":"t","topology":"single","devices":["/d/f"]}]}'
  local from_dev pbld
  from_dev="$(skeleton_build_assignment "$skeleton")"
  pbld="$(picker_build_assignment "$(skeleton_flatten_devices "$skeleton")" \
    /d/a /d/b /d/c /d/d /d/e /d/f)"
  # Are the two assignments the same JSON?
  jq -en --argjson a "$from_dev" --argjson b "$pbld" '$a == $b' >/dev/null
}

# ── AC5: an under-populated bound pool is rejected by validation ─────────────

@test "skeleton_validate: a mirror with one bound disk is rejected" {
  local skeleton='{"mode":"multi","os_pool":{"topology":"mirror","devices":["/d/a"]}}'
  run skeleton_validate "$(skeleton_flatten_devices "$skeleton")"
  [ "$status" -ne 0 ]
  local -l message="$output"   # -l: kept in lower case
  [[ "$message" == *os_pool* ]]
}
