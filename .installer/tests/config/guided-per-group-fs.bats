#!/usr/bin/env bats
# Issue 09 (AC4) integration: the per-group filesystem/encryption the Guided
# Installer's pool editor AUTHORS assembles into a Config State that passes the
# issue-01 validation contract (lib/config/validation.sh). This bridges the
# editor (guided-controller.sh) to the validator — the editor's single-disk pin
# for ext4/xfs is what keeps the authored config inside the passing set.

setup() {
  TEST_DIR="$(mktemp -d)"
  export GUIDED_STATE_FILE="$TEST_DIR/state.json"
  export GUIDED_NAV_FILE="$TEST_DIR/nav.json"
  export GUIDED_BASELINE_FILE="$TEST_DIR/base.json"
  export CONFIG_FILE="$TEST_DIR/install.jsonc"

  # Validation harness stubs (mirror validation-group-filesystem.bats): the
  # accessors read CONFIG_FILE via cfgo; error() exits so `run` captures a reject.
  jsonc_strip() { cat "$1"; }
  cfgo() { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  cfg()  { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  error() { echo "ERROR: $*" >&2; exit 1; }
  info() { :; }; section() { :; }; warn() { :; }
  export -f jsonc_strip cfgo cfg error info section warn

  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/nav.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/edits.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"
  source "$BATS_TEST_DIRNAME/../../lib/guided-controller.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/accessors.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/validation.sh"

  printf '%s\n' '{}' > "$GUIDED_STATE_FILE"
  printf '%s\n' '{}' > "$GUIDED_BASELINE_FILE"
  printf '%s\n' '{"screen":"top"}' > "$GUIDED_NAV_FILE"
}
teardown() { rm -rf "$TEST_DIR"; }

set_nav() { printf '%s\n' "$1" > "$GUIDED_NAV_FILE"; }

# Author a zfs root + one ext4 data group entirely through the pool editor, then
# validate the assembled config. With an empty baseline the authored Config State
# IS the Effective Config, so we validate it directly.
@test "AC4: a guided-authored zfs-root + encrypted ext4 data group validates" {
  set_nav "$(nav_to_datapools Disks)"
  guided_ctl_enter "+ Add data pool" >/dev/null      # tank0: zfs stripe ×1
  set_nav "$(nav_to_pooledit Disks 0)"
  guided_ctl_enter "filesystem: zfs   (Enter cycles)"   >/dev/null  # → btrfs
  guided_ctl_enter "filesystem: btrfs   (Enter cycles)" >/dev/null  # → ext4 (pins)
  guided_ctl_enter "encryption: false   (Enter toggles)" >/dev/null # → true

  cp "$GUIDED_STATE_FILE" "$CONFIG_FILE"

  # the editor pinned ext4 to single-disk and recorded the per-group choices
  [ "$(jq -r '.data_pools[0].filesystem' "$CONFIG_FILE")" = "ext4" ]
  [ "$(jq -r '.data_pools[0].topology'   "$CONFIG_FILE")" = "single" ]
  [ "$(jq -r '.data_pools[0].disk_count' "$CONFIG_FILE")" = "1" ]
  [ "$(jq -r '.data_pools[0].encryption' "$CONFIG_FILE")" = "true" ]

  run _validation_group_filesystems
  [ "$status" -eq 0 ]
  run _validation_filesystem
  [ "$status" -eq 0 ]
}

# A btrfs group authored with native raid also validates (raid1 is legal btrfs).
@test "AC4: a guided-authored btrfs raid1 data group validates" {
  set_nav "$(nav_to_datapools Disks)"
  guided_ctl_enter "+ Add data pool" >/dev/null      # tank0: zfs stripe ×1
  set_nav "$(nav_to_pooledit Disks 0)"
  guided_ctl_enter "filesystem: zfs   (Enter cycles)" >/dev/null    # → btrfs (topo→single)
  guided_ctl_enter "topology: single   (Enter cycles)" >/dev/null   # → raid0
  guided_ctl_enter "topology: raid0   (Enter cycles)"  >/dev/null   # → raid1

  cp "$GUIDED_STATE_FILE" "$CONFIG_FILE"
  [ "$(jq -r '.data_pools[0].filesystem' "$CONFIG_FILE")" = "btrfs" ]
  [ "$(jq -r '.data_pools[0].topology'   "$CONFIG_FILE")" = "raid1" ]

  run _validation_group_filesystems
  [ "$status" -eq 0 ]
}

# Non-vacuous: bypassing the editor's pin (an ext4 pool with disk_count > 1) is
# what validation rejects — i.e. the pin is load-bearing, not decorative.
@test "AC4: an unpinned ext4 group (disk_count 2) is rejected by validation" {
  printf '%s\n' \
    '{"data_pools":[{"name":"tank0","filesystem":"ext4","topology":"single","disk_count":2}]}' \
    > "$CONFIG_FILE"
  run _validation_group_filesystems
  [ "$status" -ne 0 ]
}
