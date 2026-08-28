#!/usr/bin/env bats
# Tests for .os/lib/config/history.sh — the Guided Installer's Undo/Redo
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

  # shellcheck source=../../lib/config/state.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  # shellcheck source=../../lib/config/history.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/history.sh"
}

# A Config State carrying one override, used as a recognisable present.
host() { cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"'; }

# ── tracer: a fresh history surfaces its seed state, nothing to undo ─────────

@test "hist_new: surfaces the seed state and has nothing to undo" {
  h="$(hist_new "$(host)")"

  run hist_present "$h"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.hostname == "eterniox"'

  run hist_can_undo "$h"
  [ "$status" -ne 0 ]
}

# ── commit: the new state becomes the present and an undo target appears ─────

@test "hist_commit: the committed state becomes the present, undo now offered" {
  h="$(hist_new "$(cfgstate_new)")"
  h="$(hist_commit "$h" "$(host)")"

  run hist_present "$h"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.hostname == "eterniox"'

  run hist_can_undo "$h"
  [ "$status" -eq 0 ]
}

# ── undo: the prior present is restored and a redo target appears ────────────

@test "hist_undo: restores the prior present and offers a redo" {
  h="$(hist_new "$(cfgstate_new)")"
  h="$(hist_commit "$h" "$(host)")"
  h="$(hist_undo "$h")"

  run hist_present "$h"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. == {}'        # back to the empty seed

  run hist_can_undo "$h"
  [ "$status" -ne 0 ]                       # nothing earlier to undo

  run hist_can_redo "$h"
  [ "$status" -eq 0 ]                       # the undone edit can be redone
}

# ── redo: the undone present is re-applied ──────────────────────────────────

@test "hist_redo: re-applies the undone present" {
  h="$(hist_new "$(cfgstate_new)")"
  h="$(hist_commit "$h" "$(host)")"
  h="$(hist_undo "$h")"
  h="$(hist_redo "$h")"

  run hist_present "$h"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.hostname == "eterniox"'

  run hist_can_redo "$h"
  [ "$status" -ne 0 ]                       # nothing left to redo

  run hist_can_undo "$h"
  [ "$status" -eq 0 ]                       # the re-applied edit can be undone
}

# ── a fresh edit after an undo abandons the redo stack ──────────────────────

@test "hist_commit: a fresh edit after an undo clears the redo stack" {
  h="$(hist_new "$(cfgstate_new)")"
  h="$(hist_commit "$h" "$(host)")"
  h="$(hist_undo "$h")"                      # redo now available
  h="$(hist_commit "$h" \
        "$(cfgstate_set "$(cfgstate_new)" mode '"mirror"')")"

  run hist_can_redo "$h"
  [ "$status" -ne 0 ]                        # the abandoned edit is gone

  run hist_present "$h"
  echo "$output" | jq -e '.mode == "mirror"'
}

# ── Reset-all is a commit of the fresh baseline, so it is itself undoable ────

@test "hist_undo: Reset-all (commit of the baseline) is undoable" {
  base="$(cfgstate_new)"
  h="$(hist_new "$base")"
  h="$(hist_commit "$h" "$(host)")"          # an operator edit
  h="$(hist_commit "$h" "$base")"            # Reset-all → back to the baseline

  run hist_present "$h"
  echo "$output" | jq -e '. == {}'           # reset took effect

  h="$(hist_undo "$h")"                       # undo the Reset-all
  run hist_present "$h"
  echo "$output" | jq -e '.system.hostname == "eterniox"'
}
