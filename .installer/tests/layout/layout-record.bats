#!/usr/bin/env bats
# Tests for the Layout Record read interface (lib/globals.sh, ADR 0043): the
# layout_* accessors that expose the multi-disk adapter's resolved model
# (per-group topology, standalone data pools, folded leftovers) so consumers
# (print_summary, pool_owners_apply) depend on the interface, not the
# adapter-private _LAYOUT_IMPL_* variables. Absence-safety is the crux: the
# accessors must not arithmetic-abort an undeclared associative array under
# `set -u` (single-disk / non-ZFS root), so every case runs under `set -u`.

GLOBALS="$BATS_TEST_DIRNAME/../../lib/globals.sh"

# Run a snippet with the record populated (the ZFS-multi model fixture).
with_model() {
  bash -uc "
    source '$GLOBALS'
    declare -gA _LAYOUT_IMPL_STORAGE_PARTS=([tank0]='/dev/sda1' [_leftover]='/dev/sdb1 /dev/sdc1')
    declare -gA _LAYOUT_IMPL_TOPOLOGIES=([tank0]='mirror' [_leftover]='independent')
    declare -gA _LAYOUT_IMPL_DATA_POOL_MOUNT=([vault]='/mnt/vault')
    declare -gA _LAYOUT_IMPL_DATA_POOL_TOPO=([vault]='raidz1')
    declare -ga _LAYOUT_IMPL_DATA_POOL_NAMES=(vault)
    declare -ga _LAYOUT_IMPL_LEFTOVER_DISKS=(/dev/sdb /dev/sdc)
    _LAYOUT_IMPL_OS_TOPOLOGY=none
    _LAYOUT_IMPL_OS_DISK=/dev/sda
    $1"
}

# Run a snippet with NO model declared (single-disk / non-ZFS root).
without_model() { bash -uc "source '$GLOBALS'; $1"; }

@test "layout_has_leftover: true when a _leftover storage part exists" {
  run with_model 'layout_has_leftover && echo YES || echo NO'
  [ "$status" -eq 0 ]
  [[ "$output" == "YES" ]]
}

@test "layout_has_leftover: false + set-u-safe when the model is absent" {
  run without_model 'layout_has_leftover && echo YES || echo NO'
  [ "$status" -eq 0 ]
  [[ "$output" == "NO" ]]
  [[ "$output" != *"unbound variable"* ]]
}

@test "layout_leftover_parts: the folded device list; empty when absent" {
  run with_model 'layout_leftover_parts'
  [ "$output" == "/dev/sdb1 /dev/sdc1" ]
  run without_model 'layout_leftover_parts; echo "[$?]"'
  [ "$output" == "[0]" ]
}

@test "layout_os_topology / layout_os_disk" {
  run with_model 'layout_os_topology'; [ "$output" == "none" ]
  run with_model 'layout_os_disk';     [ "$output" == "/dev/sda" ]
  run without_model 'echo "[$(layout_os_topology)]"'; [ "$output" == "[]" ]
}

@test "layout_leftover_disks: one per line; nothing when absent" {
  run with_model 'layout_leftover_disks'
  [ "${lines[0]}" == "/dev/sdb" ]
  [ "${lines[1]}" == "/dev/sdc" ]
  run without_model 'layout_leftover_disks'
  [ -z "$output" ]
}

@test "layout_group_topology: by group name and _leftover; empty when absent" {
  run with_model 'layout_group_topology tank0';     [ "$output" == "mirror" ]
  run with_model 'layout_group_topology _leftover'; [ "$output" == "independent" ]
  run without_model 'echo "[$(layout_group_topology tank0)]"'; [ "$output" == "[]" ]
}

@test "layout_data_pool_names + mount + topo" {
  run with_model 'layout_data_pool_names';        [ "$output" == "vault" ]
  run with_model 'layout_data_pool_mount vault';  [ "$output" == "/mnt/vault" ]
  run with_model 'layout_data_pool_topo vault';   [ "$output" == "raidz1" ]
  run without_model 'layout_data_pool_names';     [ -z "$output" ]
}
