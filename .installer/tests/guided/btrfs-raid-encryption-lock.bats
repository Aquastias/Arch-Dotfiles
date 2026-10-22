#!/usr/bin/env bats
# Encryption is locked off for a multi-disk btrfs root: the classic mkinitcpio
# `encrypt` hook opens one device, so the layout refuses the combination. The
# menu must not offer what the install refuses (found by the Combination
# Matrix, 20261022). Menu model + controller seams, no fzf, no real disks.

setup() {
  TEST_DIR="$(mktemp -d)"
  export GUIDED_STATE_FILE="$TEST_DIR/state.json"
  export GUIDED_NAV_FILE="$TEST_DIR/nav.json"
  export GUIDED_BASELINE_FILE="$TEST_DIR/base.json"

  source "$BATS_TEST_DIRNAME/../../lib/config/config-state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/navigation.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/edit.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/skeleton.sh"
  source "$BATS_TEST_DIRNAME/../../lib/guided/controller.sh"

  printf '%s\n' '{}' > "$GUIDED_STATE_FILE"
  # Proceed refuses without a user (ADR 0157), so the baseline carries one.
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_BASELINE_FILE"
  printf '%s\n' '{"screen":"top"}' > "$GUIDED_NAV_FILE"
}
teardown() { rm -rf "$TEST_DIR"; }

RAID='{"filesystem":"btrfs","mode":"multi","os_pool":{"topology":"raid1"}}'

@test "locked: a multi-disk btrfs root" {
  menu_state_encryption_locked "$RAID"
}

@test "not locked: a single-disk btrfs root" {
  ! menu_state_encryption_locked '{"filesystem":"btrfs"}'
}

@test "not locked: a multi-disk zfs root" {
  ! menu_state_encryption_locked \
    '{"filesystem":"zfs","mode":"multi","os_pool":{"topology":"mirror"}}'
}

@test "display: the Encryption row reads off (btrfs raid)" {
  printf '%s\n' '{"screen":"category","category":"Disks"}' > "$GUIDED_NAV_FILE"
  printf '%s\n' "$RAID" > "$GUIDED_STATE_FILE"
  run guided_controller_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'Encryption ▸ off (btrfs raid)'
}

@test "enter: the locked Encryption row opens no editor" {
  printf '%s\n' '{"screen":"category","category":"Disks"}' > "$GUIDED_NAV_FILE"
  printf '%s\n' "$RAID" > "$GUIDED_STATE_FILE"
  run _controller_enter_category "Encryption ▸ off (btrfs raid)"
  [ "$output" = render ]
  jq -e '.screen == "category"' "$GUIDED_NAV_FILE"
}

@test "proceed: blocked while encryption is on over a btrfs raid root" {
  jq -c '.options.encryption = true' <<<"$RAID" > "$GUIDED_STATE_FILE"
  run _controller_proceed_directive
  [[ "$output" == notice* ]]
  [[ "$output" == *"Encryption"* ]]
}

@test "proceed: no encryption notice once encryption is off" {
  printf '%s\n' "$RAID" > "$GUIDED_STATE_FILE"
  run _controller_proceed_directive
  [[ "$output" != *"btrfs raid"* ]]
}
