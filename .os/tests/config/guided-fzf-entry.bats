#!/usr/bin/env bats
# Tests for .os/lib/guided-fzf-entry.sh — the persistent-fzf bind entry point
# (ADR 0042). fzf itself can't run in CI (no tty), but the entry script's `list`
# and `dispatch` subcommands are plain commands: this drives them as a real
# subprocess (the way fzf's binds would) and asserts the rendered list, the
# emitted fzf action string, and the navigation file mutation. Only fzf's own
# invocation of these binds — and the interactive `oneshot` path — stay for the
# slice-01 VM/HITL gate.

setup() {
  ENTRY="$BATS_TEST_DIRNAME/../../lib/guided-fzf-entry.sh"
  TEST_DIR="$(mktemp -d)"
  export GUIDED_STATE_FILE="$TEST_DIR/s" GUIDED_NAV_FILE="$TEST_DIR/n" \
         GUIDED_BASELINE_FILE="$TEST_DIR/b" GUIDED_RESULT_FILE="$TEST_DIR/r"
  printf '{}\n' > "$GUIDED_STATE_FILE"
  printf '{}\n' > "$GUIDED_BASELINE_FILE"
  printf '{"screen":"top"}\n' > "$GUIDED_NAV_FILE"
}
teardown() { rm -rf "$TEST_DIR"; }

@test "entry list: renders the top menu" {
  run bash "$ENTRY" list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Host — "
  echo "$output" | grep -q "Proceed ▸"
}

@test "entry dispatch enter: drills into a category + emits a reload action" {
  run bash "$ENTRY" dispatch enter "Disks — layout, data pools, filesystem, encryption, swap"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "reload(bash"
  [ "$(jq -r '.screen' "$GUIDED_NAV_FILE")" = "category" ]
  [ "$(jq -r '.category' "$GUIDED_NAV_FILE")" = "Disks" ]
}

@test "entry dispatch enter: a terminal row writes the result + accepts" {
  run bash "$ENTRY" dispatch enter "Proceed ▸ review & install"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "+accept"
  echo "$output" | grep -q "$GUIDED_RESULT_FILE"
}

@test "entry dispatch enter: an enum field opens the value picker" {
  printf '%s\n' '{"screen":"category","category":"Disks"}' > "$GUIDED_NAV_FILE"
  run bash "$ENTRY" dispatch enter "encryption: false"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.screen' "$GUIDED_NAV_FILE")" = "values" ]
  [ "$(jq -r '.field' "$GUIDED_NAV_FILE")" = "options.encryption" ]
}

@test "entry dispatch back: at the top screen, aborts" {
  run bash "$ENTRY" dispatch back ""
  [ "$status" -eq 0 ]
  [ "$output" = "abort" ]
}

@test "entry key: ctrl-z emits a render action over the history file" {
  bash -c '. "'"$BATS_TEST_DIRNAME"'/../../lib/config/history.sh"; hist_new "{}"' \
    > "$TEST_DIR/hist"
  export GUIDED_HIST_FILE="$TEST_DIR/hist"
  run bash "$ENTRY" key ctrl-z
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "clear-query+reload(bash"
}
