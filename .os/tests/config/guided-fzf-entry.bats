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
         GUIDED_BASELINE_FILE="$TEST_DIR/b" GUIDED_RESULT_FILE="$TEST_DIR/r" \
         GUIDED_POS_FILE="$TEST_DIR/pos"
  printf '{}\n' > "$GUIDED_STATE_FILE"
  printf '{}\n' > "$GUIDED_BASELINE_FILE"
  printf '{"screen":"top"}\n' > "$GUIDED_NAV_FILE"
  : > "$GUIDED_POS_FILE"
}
teardown() { rm -rf "$TEST_DIR"; }

@test "entry list: renders the top menu" {
  run bash "$ENTRY" list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "System — "
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
  run bash "$ENTRY" dispatch enter "Filesystem: ZFS"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.screen' "$GUIDED_NAV_FILE")" = "values" ]
  [ "$(jq -r '.field' "$GUIDED_NAV_FILE")" = "filesystem" ]
}

@test "entry dispatch enter: a credential row executes the masked capture" {
  # The root password lives behind the Root Editor now (ADR 0063); its password
  # row drops to the masked capture (execute() fallback without rich chrome).
  printf '{"screen":"rooteditor","category":"Users"}\n' > "$GUIDED_NAV_FILE"
  run bash "$ENTRY" dispatch enter "password: (not set)"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "execute(bash"
  echo "$output" | grep -q "secret root"
}

@test "entry dispatch back: at the top screen, aborts" {
  run bash "$ENTRY" dispatch back ""
  [ "$status" -eq 0 ]
  [ "$output" = "abort" ]
}

@test "entry dispatch back: category→top stashes the exited category's line" {
  printf '%s\n' '{"screen":"category","category":"Disks"}' > "$GUIDED_NAV_FILE"
  run bash "$ENTRY" dispatch back ""
  [ "$status" -eq 0 ]
  # Disks is the 10th row of the top list — stashed for the load bind's pos, so
  # Esc-back lands there, not on a spacer/header (the reported bug). The reload
  # action must NOT inline pos (it would target the pre-reload list).
  [ "$(cat "$GUIDED_POS_FILE")" = "10" ]
  echo "$output" | grep -vq "pos("
  [ "$(jq -r '.screen' "$GUIDED_NAV_FILE")" = "top" ]
}

@test "entry dispatch back: values→category stashes the exited field's line" {
  printf '%s\n' \
    '{"screen":"values","category":"Disks","field":"filesystem","label":"Filesystem"}' \
    > "$GUIDED_NAV_FILE"
  run bash "$ENTRY" dispatch back ""
  [ "$status" -eq 0 ]
  # "Filesystem: ZFS" is the 4th row of the Disks category screen.
  [ "$(cat "$GUIDED_POS_FILE")" = "4" ]
  [ "$(jq -r '.screen' "$GUIDED_NAV_FILE")" = "category" ]
}

@test "entry poshint: emits the stashed pos once, then clears it" {
  printf '10' > "$GUIDED_POS_FILE"
  run bash "$ENTRY" poshint
  [ "$status" -eq 0 ]
  [ "$output" = "pos(10)" ]
  [ -z "$(cat "$GUIDED_POS_FILE")" ]        # consumed (one-shot)
  run bash "$ENTRY" poshint                  # second load → no re-jump
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "entry key: ctrl-z emits a render action over the history file" {
  bash -c '. "'"$BATS_TEST_DIRNAME"'/../../lib/config/history.sh"; hist_new "{}"' \
    > "$TEST_DIR/hist"
  export GUIDED_HIST_FILE="$TEST_DIR/hist"
  run bash "$ENTRY" key ctrl-z
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "clear-query+reload(bash"
}
