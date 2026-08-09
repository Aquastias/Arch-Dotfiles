#!/usr/bin/env bats
# Tests the Proceed-only terminal-action gate for Manual Partitioning (ADR
# 0073): the top screen offers Save profile / Export config on the auto path,
# and withholds both while manual is active — Proceed always stays. Controller
# seam, no fzf, no real disks.

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
  source "$BATS_TEST_DIRNAME/../../lib/guided-controller.sh"

  printf '%s\n' '{}' > "$GUIDED_BASELINE_FILE"
  printf '%s\n' '{"screen":"top"}' > "$GUIDED_NAV_FILE"
}
teardown() { rm -rf "$TEST_DIR"; }

set_state() { printf '%s\n' "$1" > "$GUIDED_STATE_FILE"; }

@test "top rows: the auto path offers Proceed, Save and Export" {
  set_state '{}'
  run guided_ctl_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^Proceed'
  echo "$output" | grep -q '^Save profile'
  echo "$output" | grep -q '^Export config'
}

@test "top rows: manual withholds Save and Export, keeps Proceed" {
  set_state '{"disk_config":{"kind":"manual"}}'
  run guided_ctl_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^Proceed'
  ! echo "$output" | grep -q '^Save profile'
  ! echo "$output" | grep -q '^Export config'
}
