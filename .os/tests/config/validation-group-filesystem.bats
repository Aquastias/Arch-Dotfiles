#!/usr/bin/env bats
# Per-group filesystem/encryption — accessors + the validation contract over
# data_pools[] and storage_groups[] (ADR 0043). A group (a Standalone Data Pool
# or a Storage Group) may declare its own `filesystem` (defaulting to the root
# `filesystem`) and an independent `encryption` bool. The contract enforces:
# known filesystem; topology valid for that filesystem; ext4/xfs are single-disk
# only. Whether an adapter is *built* is the layout-dispatch seam's job — these
# are config-sanity checks, like validation-filesystem.bats.
#
# Strategy mirrors validation-filesystem.bats: stub helpers, drive accessors via
# CONFIG_FILE, assert error() fires (exit 1) on a bad combination.

setup() {
  TEST_DIR="$(mktemp -d)"
  export CONFIG_FILE="$TEST_DIR/install.jsonc"
  jsonc_strip() { cat "$1"; }
  jsonc_read() { jsonc_strip "$1" | jq -r "$2"; }
  cfgo()    { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  cfg()     { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  error()   { echo "ERROR: $*" >&2; exit 1; }
  info()    { :; }
  section() { :; }
  warn()    { :; }
  export -f jsonc_strip jsonc_read cfgo cfg error info section warn

  # shellcheck source=../../lib/config/accessors.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/accessors.sh"
  # shellcheck source=../../lib/config/validation.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/validation.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

write_config() { printf '%s\n' "$1" > "$CONFIG_FILE"; }

# ── accessor: per-pool filesystem inherits the root filesystem when absent ───

@test "data_pool filesystem: absent inherits the root filesystem" {
  write_config '{"filesystem":"btrfs","data_pools":[{"name":"tank0"}]}'
  run install_config_data_pool_filesystem 0
  [ "$status" -eq 0 ]
  [ "$output" = "btrfs" ]
}

@test "data_pool filesystem: an explicit value wins over the root" {
  write_config '{"filesystem":"zfs",
    "data_pools":[{"name":"tank0","filesystem":"ext4"}]}'
  run install_config_data_pool_filesystem 0
  [ "$status" -eq 0 ]
  [ "$output" = "ext4" ]
}

# ── contract: each group filesystem must be a known filesystem ───────────────

@test "contract: an unknown data_pool filesystem is rejected, naming the pool" {
  write_config '{"data_pools":[{"name":"tank0","filesystem":"reiserfs"}]}'
  run _validation_group_filesystems
  [ "$status" -ne 0 ]
  [[ "$output" =~ "tank0" ]]
  [[ "$output" =~ "filesystem" ]]
}

@test "contract: all-known group filesystems pass" {
  write_config '{"filesystem":"zfs",
    "data_pools":[{"name":"tank0","filesystem":"ext4","disk_count":1}]}'
  run _validation_group_filesystems
  [ "$status" -eq 0 ]
}

# ── contract: ext4/xfs are single-disk only ──────────────────────────────────

@test "contract: an ext4 pool with disk_count > 1 is rejected, naming the pool" {
  write_config '{"data_pools":[{"name":"tank0","filesystem":"ext4",
    "disk_count":2}]}'
  run _validation_group_filesystems
  [ "$status" -ne 0 ]
  [[ "$output" =~ "tank0" ]]
}

@test "contract: an xfs pool with disk_count > 1 is rejected" {
  write_config '{"data_pools":[{"name":"tank0","filesystem":"xfs",
    "disk_count":3}]}'
  run _validation_group_filesystems
  [ "$status" -ne 0 ]
  [[ "$output" =~ "tank0" ]]
}

@test "contract: a zfs pool with disk_count > 1 is allowed" {
  write_config '{"data_pools":[{"name":"tank0","filesystem":"zfs",
    "topology":"mirror","disk_count":2}]}'
  run _validation_group_filesystems
  [ "$status" -eq 0 ]
}

# ── contract: topology must be valid for the group's filesystem ──────────────

@test "contract: an ext4 pool with an explicit non-single topology is rejected" {
  write_config '{"data_pools":[{"name":"tank0","filesystem":"ext4",
    "topology":"mirror"}]}'
  run _validation_group_filesystems
  [ "$status" -ne 0 ]
  [[ "$output" =~ "tank0" ]]
}

@test "contract: an ext4 pool with no topology passes (stripe default ignored)" {
  write_config '{"data_pools":[{"name":"tank0","filesystem":"ext4"}]}'
  run _validation_group_filesystems
  [ "$status" -eq 0 ]
}

@test "contract: an ext4 pool with explicit single topology passes" {
  write_config '{"data_pools":[{"name":"tank0","filesystem":"ext4",
    "topology":"single"}]}'
  run _validation_group_filesystems
  [ "$status" -eq 0 ]
}

@test "contract: a btrfs pool accepts native raid1/raid10 topology" {
  write_config '{"data_pools":[
    {"name":"tank0","filesystem":"btrfs","topology":"raid1","disk_count":2},
    {"name":"tank1","filesystem":"btrfs","topology":"raid10","disk_count":4}]}'
  run _validation_group_filesystems
  [ "$status" -eq 0 ]
}

@test "contract: a btrfs pool rejects a zfs-only topology (raidz1)" {
  write_config '{"data_pools":[{"name":"tank0","filesystem":"btrfs",
    "topology":"raidz1","disk_count":3}]}'
  run _validation_group_filesystems
  [ "$status" -ne 0 ]
  [[ "$output" =~ "tank0" ]]
}

@test "contract: a zfs pool accepts raidz2 topology" {
  write_config '{"data_pools":[{"name":"tank0","filesystem":"zfs",
    "topology":"raidz2","disk_count":4}]}'
  run _validation_group_filesystems
  [ "$status" -eq 0 ]
}

@test "contract: a zfs storage group accepts independent topology" {
  write_config '{"storage_groups":[{"name":"bulk","topology":"independent",
    "disk_count":3}]}'
  run _validation_group_filesystems
  [ "$status" -eq 0 ]
}

@test "contract: a zfs pool accepts the raidz alias topology" {
  write_config '{"data_pools":[{"name":"tank0","topology":"raidz",
    "disk_count":3}]}'
  run _validation_group_filesystems
  [ "$status" -eq 0 ]
}

# ── accessor: per-pool encryption is an independent bool, default false ──────

@test "data_pool encryption: absent defaults to false" {
  write_config '{"data_pools":[{"name":"tank0"}]}'
  run install_config_data_pool_encryption 0
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "data_pool encryption: an explicit false round-trips as false" {
  write_config '{"data_pools":[{"name":"tank0","encryption":false}]}'
  run install_config_data_pool_encryption 0
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "data_pool encryption: an explicit true is true" {
  write_config '{"data_pools":[{"name":"tank0","encryption":true}]}'
  run install_config_data_pool_encryption 0
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# ── storage_groups[] get the same per-group filesystem treatment ─────────────

@test "storage_group filesystem: absent inherits the root filesystem" {
  write_config '{"filesystem":"btrfs","storage_groups":[{"name":"bulk"}]}'
  run install_config_storage_group_filesystem 0
  [ "$status" -eq 0 ]
  [ "$output" = "btrfs" ]
}

@test "contract: an unknown storage_group filesystem is rejected, naming it" {
  write_config '{"storage_groups":[{"name":"bulk","filesystem":"jfs"}]}'
  run _validation_group_filesystems
  [ "$status" -ne 0 ]
  [[ "$output" =~ "bulk" ]]
}

@test "contract: an ext4 storage_group with disk_count > 1 is rejected" {
  write_config '{"storage_groups":[{"name":"bulk","filesystem":"ext4",
    "disk_count":2}]}'
  run _validation_group_filesystems
  [ "$status" -ne 0 ]
  [[ "$output" =~ "bulk" ]]
}

@test "storage_group encryption: explicit false round-trips as false" {
  write_config '{"storage_groups":[{"name":"bulk","encryption":false}]}'
  run install_config_storage_group_encryption 0
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}
