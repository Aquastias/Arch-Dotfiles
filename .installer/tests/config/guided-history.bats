#!/usr/bin/env bats
# Tests for .installer/lib/config/history.sh — the Guided Installer's Undo/Redo
# snapshot stack (ADR 0039, issue 02): a past/present/future history over the
# Config State, so navigation is non-destructive. Every mutating action is one
# commit (one undo step); a fresh edit after an undo clears the redo stack;
# Reset-all is just a commit and so is itself undoable. Pure: JSON-in/JSON-out,
# no TTY.
#
# Behaviour under test (external only — the Config State a history surfaces and
# the undo/redo availability it reports), never internal structure.

setup() {
  error() { echo "[error] $*" >&2; return 1; }
  export -f error

  # shellcheck source=../../lib/config/config-state.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/config-state.sh"
  # shellcheck source=../../lib/config/history.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/history.sh"
}

# A Config State carrying one override, used as a recognisable present.
host() { config_state_set "$(config_state_new)" system.hostname '"eterniox"'; }

# ── tracer: a fresh history surfaces its seed state, nothing to undo ─────────

@test "history_new: surfaces the seed state and has nothing to undo" {
  h="$(history_new "$(host)")"

  run history_present "$h"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.hostname == "eterniox"'

  run history_can_undo "$h"
  [ "$status" -ne 0 ]
}

# ── commit: the new state becomes the present and an undo target appears ─────

@test "history_commit: the committed state becomes the present, undo now offered" {
  h="$(history_new "$(config_state_new)")"
  h="$(history_commit "$h" "$(host)")"

  run history_present "$h"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.hostname == "eterniox"'

  run history_can_undo "$h"
  [ "$status" -eq 0 ]
}

# ── undo: the prior present is restored and a redo target appears ────────────

@test "history_undo: restores the prior present and offers a redo" {
  h="$(history_new "$(config_state_new)")"
  h="$(history_commit "$h" "$(host)")"
  h="$(history_undo "$h")"

  run history_present "$h"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. == {}'        # back to the empty seed

  run history_can_undo "$h"
  [ "$status" -ne 0 ]                       # nothing earlier to undo

  run history_can_redo "$h"
  [ "$status" -eq 0 ]                       # the undone edit can be redone
}

# ── redo: the undone present is re-applied ──────────────────────────────────

@test "history_redo: re-applies the undone present" {
  h="$(history_new "$(config_state_new)")"
  h="$(history_commit "$h" "$(host)")"
  h="$(history_undo "$h")"
  h="$(history_redo "$h")"

  run history_present "$h"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.hostname == "eterniox"'

  run history_can_redo "$h"
  [ "$status" -ne 0 ]                       # nothing left to redo

  run history_can_undo "$h"
  [ "$status" -eq 0 ]                       # the re-applied edit can be undone
}

# ── a fresh edit after an undo abandons the redo stack ──────────────────────

@test "history_commit: a fresh edit after an undo clears the redo stack" {
  h="$(history_new "$(config_state_new)")"
  h="$(history_commit "$h" "$(host)")"
  h="$(history_undo "$h")"                      # redo now available
  h="$(history_commit "$h" \
        "$(config_state_set "$(config_state_new)" mode '"mirror"')")"

  run history_can_redo "$h"
  [ "$status" -ne 0 ]                        # the abandoned edit is gone

  run history_present "$h"
  echo "$output" | jq -e '.mode == "mirror"'
}

# ── Reset-all is a commit of the fresh baseline, so it is itself undoable ────

@test "history_undo: Reset-all (commit of the baseline) is undoable" {
  base="$(config_state_new)"
  h="$(history_new "$base")"
  h="$(history_commit "$h" "$(host)")"          # an operator edit
  h="$(history_commit "$h" "$base")"            # Reset-all → back to the baseline

  run history_present "$h"
  echo "$output" | jq -e '. == {}'           # reset took effect

  h="$(history_undo "$h")"                       # undo the Reset-all
  run history_present "$h"
  echo "$output" | jq -e '.system.hostname == "eterniox"'
}
