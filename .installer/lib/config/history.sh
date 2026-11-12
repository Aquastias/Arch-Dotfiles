#!/usr/bin/env bash
# =============================================================================
# lib/config/history.sh — Guided Installer Undo/Redo stack (ADR 0039, issue 02)
# =============================================================================
# A snapshot stack over the Config State so navigation is non-destructive. The
# classic past / present / future model: the present is the live Config State;
# `history_commit` pushes the old present onto `past` and clears `future`, so
# every mutating action (field edit, reset, list add/remove — including
# Reset-all) is exactly one undo step. `history_undo`/`history_redo` shuttle the
# present between the two stacks; a fresh commit after an undo clears the redo
# stack.
#
# Pure: in-memory JSON on stdin/args → JSON on stdout, no TTY. The present is a
# Config State (sparse override map); this module is agnostic to its contents.
#
# Public API:
#   history_new      <state>          → history seeded with <state> as present
#   history_present  <history>        → the current Config State on stdout
#   history_commit   <history> <state>→ history with <state> as the new present
#   history_undo     <history>        → history with the prior present
#                                       (no-op none)
#   history_redo     <history>        → history with the re-applied present
#                                       (no-op)
#   history_can_undo <history>        → rc 0 if an undo target exists, else 1
#   history_can_redo <history>        → rc 0 if a redo target exists, else 1
#
# Used by: lib/guided/controller.sh, lib/guided/shell.sh.
# =============================================================================
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

# history_new <state> — a fresh history with <state> as the present, empty
# stacks.
history_new() {
  # The state as the present, with empty stacks.
  jq --argjson s "$1" -n '{past: [], present: $s, future: []}'
}

# history_present <history> — the current Config State (override map) on stdout.
history_present() { printf '%s\n' "$1" | jq '.present'; }

# history_commit <history> <state> — record <state> as the new present: the old
# present is pushed onto `past` and `future` is cleared (a fresh edit after an
# undo abandons the redo stack). One commit = one undo step.
history_commit() {
  local commit='{past: (.past + [.present]), present: $s, future: []}'
  # The history with <state> as its present.
  printf '%s\n' "$1" | jq --argjson s "$2" "$commit"
}

# history_undo <history> — restore the prior present: pop `past`, pushing the
# current present onto `future` so it can be redone. A no-op when `past` is
# empty (nothing earlier to restore).
history_undo() {
  local undo='{past: .past[:-1], present: .past[-1],'
  undo+=' future: ([.present] + .future)}'
  if ! history_can_undo "$1"; then
    # Unchanged (nothing to move).
    printf '%s\n' "$1" | jq '.'
    return 0
  fi
  # The history one step back.
  printf '%s\n' "$1" | jq "$undo"
}

# history_redo <history> — re-apply the most recently undone present: pop
# `future`, pushing the current present back onto `past`. A no-op when `future`
# is empty (nothing to redo).
history_redo() {
  local redo='{past: (.past + [.present]), present: .future[0],'
  redo+=' future: .future[1:]}'
  if ! history_can_redo "$1"; then
    # Unchanged (nothing to move).
    printf '%s\n' "$1" | jq '.'
    return 0
  fi
  # The history one step forward.
  printf '%s\n' "$1" | jq "$redo"
}

# history_can_undo <history> — rc 0 when there is a prior state to restore.
history_can_undo() {
  # Is there an earlier state?
  printf '%s\n' "$1" | jq -e '.past | length > 0' >/dev/null
}

# history_can_redo <history> — rc 0 when an undone state can be re-applied.
history_can_redo() {
  # Is there an undone state?
  printf '%s\n' "$1" | jq -e '.future | length > 0' >/dev/null
}
