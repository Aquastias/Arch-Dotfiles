#!/usr/bin/env bats
# The Backup "zfs snapshots" toggle is shown-but-locked (forced off) when the
# Config State puts no ZFS anywhere (ADR 0041): the install skips
# zfs-auto-snapshot there, so the menu must not offer it either.

setup() {
  TEST_DIR="$(mktemp -d)"
  export GUIDED_STATE_FILE="$TEST_DIR/state.json"
  export GUIDED_NAV_FILE="$TEST_DIR/nav.json"
  export GUIDED_BASELINE_FILE="$TEST_DIR/base.json"

  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/nav.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/edits.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/skeleton.sh"
  source "$BATS_TEST_DIRNAME/../../lib/guided/controller.sh"

  printf '%s\n' '{}' > "$GUIDED_STATE_FILE"
  printf '%s\n' '{}' > "$GUIDED_BASELINE_FILE"
  printf '%s\n' '{"screen":"top"}' > "$GUIDED_NAV_FILE"
}
teardown() { rm -rf "$TEST_DIR"; }

SNAP=post_install.backup.zfs_auto_snapshot
snap_locked() { jq -e ".[] | select(.field == \"$SNAP\") | .locked"; }

@test "any_zfs: default (zfs root) is true" {
  menu_state_any_zfs '{}'
}

@test "any_zfs: ext4 root, no groups is false" {
  ! menu_state_any_zfs '{"filesystem":"ext4"}'
}

@test "any_zfs: ext4 root with a zfs data pool is true" {
  menu_state_any_zfs '{"filesystem":"ext4",
    "data_pools":[{"filesystem":"zfs"}]}'
}

@test "any_zfs: a group without its own fs inherits the ext4 root" {
  ! menu_state_any_zfs '{"filesystem":"ext4","storage_groups":[{}]}'
}

@test "any_zfs: manual partitioning is false even on the zfs default" {
  ! menu_state_any_zfs '{"disk_config":{"kind":"manual"}}'
}

@test "menu_rows: zfs snapshots is unlocked on a zfs install" {
  run menu_rows '{}'
  [ "$status" -eq 0 ]
  echo "$output" | snap_locked | grep -qx false
}

@test "menu_rows: zfs snapshots is locked on an ext4 install" {
  run menu_rows '{"filesystem":"ext4"}'
  echo "$output" | snap_locked | grep -qx true
}

@test "menu_rows: the baseline filesystem counts (merged state)" {
  run menu_rows '{}' '{"filesystem":"xfs"}'
  echo "$output" | snap_locked | grep -qx true
}

@test "menu_rows: borg is never zfs-locked" {
  run menu_rows '{"filesystem":"ext4"}'
  echo "$output" | jq -e '.[] | select(.field == "post_install.backup.borg")
    | .locked == false'
}

@test "apply: toggling zfs snapshots is a no-op without ZFS" {
  local st='{"filesystem":"ext4"}'
  run _ctl_apply_enum "$st" "$SNAP" false
  [ "$status" -eq 1 ]
  [ "$output" = "$st" ]
}

@test "apply: toggling zfs snapshots works on a zfs install" {
  run _ctl_apply_enum '{}' "$SNAP" false
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.post_install.backup.zfs_auto_snapshot == false'
}

@test "Backup screen: renders off (no ZFS) on an ext4 install" {
  printf '%s\n' '{"filesystem":"ext4"}' > "$GUIDED_STATE_FILE"
  printf '%s\n' '{"screen":"category","category":"Backup"}' \
    > "$GUIDED_NAV_FILE"
  run guided_ctl_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"off (no ZFS)"* ]]
}

@test "Backup screen: renders the toggle value on a zfs install" {
  printf '%s\n' '{"screen":"category","category":"Backup"}' \
    > "$GUIDED_NAV_FILE"
  run guided_ctl_list
  [ "$status" -eq 0 ]
  [[ "$output" != *"no ZFS"* ]]
  [[ "$output" == *"ZFS snapshots: true"* ]]
}
