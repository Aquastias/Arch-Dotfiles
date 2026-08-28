#!/usr/bin/env bats
# Tests for the Manual Partitioning disk-config kind (ADR 0073): the
# `disk_config.kind` discriminator and the `disk_config.partitions[]`
# assignment join the closed host schema, and the typed accessors read them.
# `kind` absent resolves to `auto`, so every existing config is untouched.
#
# Strategy mirrors validation-filesystem.bats: stub the common helpers, drive
# the accessors from CONFIG_FILE, and validate JSON against the host schema.

setup() {
  TEST_DIR="$(mktemp -d)"
  export CONFIG_FILE="$TEST_DIR/install.jsonc"
  jsonc_strip() { cat "$1"; }
  jsonc_read()  { jsonc_strip "$1" | jq -r "$2"; }
  cfgo()        { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  cfg()         { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  error()       { echo "ERROR: $*" >&2; exit 1; }
  info() { :; }; section() { :; }; warn() { :; }
  export -f jsonc_strip jsonc_read cfgo cfg error info section warn

  # shellcheck source=../../lib/config/accessors.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/accessors.sh"
  # shellcheck source=../../lib/config/profile.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/profile.sh"
}

teardown() { rm -rf "$TEST_DIR"; }
write_config() { printf '%s\n' "$1" > "$CONFIG_FILE"; }

MANUAL='{
  "disk_config": {
    "kind": "manual",
    "partitions": [
      {"device":"/dev/sda1","mountpoint":"/boot/efi","fs":"fat32","format":true},
      {"device":"/dev/sda2","mountpoint":"/","fs":"ext4","format":true},
      {"device":"/dev/sda3","mountpoint":"/home","fs":"xfs","format":false}
    ]
  }
}'

# ── schema: the new keys are enumerated; unknown ones still abort ────────────

@test "schema: a manual disk_config validates against the host schema" {
  run validate_config_schema host "$MANUAL"
  [ "$status" -eq 0 ]
}

@test "schema: an unknown key under disk_config aborts" {
  run validate_config_schema host \
    '{"disk_config":{"kind":"manual","bogus":1}}'
  [ "$status" -ne 0 ]
}

# ── accessor: the kind discriminator ────────────────────────────────────────

@test "accessor: disk_kind defaults to auto when absent" {
  write_config '{}'
  [ "$(install_config_disk_kind)" = "auto" ]
}

@test "accessor: disk_kind reads manual" {
  write_config "$MANUAL"
  [ "$(install_config_disk_kind)" = "manual" ]
}

# ── accessor: the partitions[] assignment ───────────────────────────────────

@test "accessor: partitions_count reflects the assignment length" {
  write_config "$MANUAL"
  [ "$(install_config_partitions_count)" = "3" ]
}

@test "accessor: partition fields read by index" {
  write_config "$MANUAL"
  [ "$(install_config_partition_device 1)"     = "/dev/sda2" ]
  [ "$(install_config_partition_mountpoint 1)" = "/" ]
  [ "$(install_config_partition_fs 1)"         = "ext4" ]
}

@test "accessor: format defaults true, is false only when set false" {
  write_config "$MANUAL"
  [ "$(install_config_partition_format 1)" = "true" ]   # explicit true
  [ "$(install_config_partition_format 2)" = "false" ]  # kept /home
}

@test "accessor: partitions_json round-trips into the planner shape" {
  write_config "$MANUAL"
  run install_config_partitions_json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq 'length')" = "3" ]
}

# ── any_zfs guard: a manual layout is always poolless ───────────────────────

@test "any_zfs: a manual layout is false despite the zfs filesystem default" {
  write_config "$MANUAL"
  [ "$(install_config_any_zfs)" = "false" ]
}

@test "any_zfs: an auto layout on the default zfs filesystem is true" {
  write_config '{}'
  [ "$(install_config_any_zfs)" = "true" ]
}

# ── manual neutralises the pool-dependent options (ADR 0073) ────────────────
# The menu locks impermanence/encryption but keeps their value (non-destructive
# toggle); the back-end must still see them OFF under manual, or it would run
# impermanence setup / expect LUKS on a plain hand-partitioned root.

@test "manual: impermanence reads false even when the override is on" {
  write_config '{"disk_config":{"kind":"manual"},
                "options":{"impermanence":{"enabled":true}}}'
  [ "$(install_config_impermanence_enabled)" = "false" ]
}

@test "manual: encryption reads false even when the override is on" {
  write_config '{"disk_config":{"kind":"manual"},"options":{"encryption":true}}'
  [ "$(install_config_encryption_enabled)" = "false" ]
}

@test "auto: impermanence and encryption are honoured as authored" {
  write_config '{"options":{"impermanence":{"enabled":true},"encryption":true}}'
  [ "$(install_config_impermanence_enabled)" = "true" ]
  [ "$(install_config_encryption_enabled)" = "true" ]
}
