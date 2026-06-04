#!/usr/bin/env bats
# Tests for .os/lib/wipe-targets.sh — the Target Resolver.
#
# The Single Entry Point resolves the install's target disks from the Install
# Config and passes them to the wipe as an explicit list, so the wipe touches
# only disks the install will use and stays config-agnostic. wipe_resolve_targets
# is the pure decision: a config path → the set of target device paths, deduped.
#
# Pure module — no real block devices. We write a temp config and assert the
# resolved set, following the install-config.bats temp-CONFIG_FILE convention.

setup() {
  TEST_DIR="$(mktemp -d)"
  CFG="$TEST_DIR/install.jsonc"
  # shellcheck source=../lib/wipe-targets.sh
  source "$BATS_TEST_DIRNAME/../lib/wipe-targets.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

write_cfg() { printf '%s\n' "$1" > "$CFG"; }

@test "single mode: resolves the lone .disk" {
  write_cfg '{ "disk": "/dev/sda" }'
  run wipe_resolve_targets "$CFG"
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sda" ]
}

@test "multi mode: resolves os_pool.disks" {
  write_cfg '{ "os_pool": { "disks": ["/dev/nvme0n1", "/dev/nvme1n1"] } }'
  run wipe_resolve_targets "$CFG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/dev/nvme0n1"* ]]
  [[ "$output" == *"/dev/nvme1n1"* ]]
}

@test "union: os_pool + storage_groups + data_pools disks" {
  write_cfg '{
    "os_pool":        { "disks": ["/dev/nvme0n1"] },
    "storage_groups": [ { "disks": ["/dev/sda", "/dev/sdb"] } ],
    "data_pools":     [ { "name": "tank", "disks": ["/dev/sdc"] } ]
  }'
  run wipe_resolve_targets "$CFG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/dev/nvme0n1"* ]]
  [[ "$output" == *"/dev/sda"* ]]
  [[ "$output" == *"/dev/sdb"* ]]
  [[ "$output" == *"/dev/sdc"* ]]
}

@test "dedup: a disk named in two places appears once" {
  write_cfg '{
    "os_pool":    { "disks": ["/dev/sda"] },
    "data_pools": [ { "name": "tank", "disks": ["/dev/sda"] } ]
  }'
  run wipe_resolve_targets "$CFG"
  [ "$status" -eq 0 ]
  [ "$(grep -c "^/dev/sda$" <<<"$output")" -eq 1 ]
}

@test "no disks declared: resolves to nothing" {
  write_cfg '{ "system": { "hostname": "box" } }'
  run wipe_resolve_targets "$CFG"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
