#!/usr/bin/env bash
# =============================================================================
# lib/guided-rows.sh — top-list row classifier (ADR 0083)
# =============================================================================
# fzf has no non-selectable items, so the cursor CAN land on the decorative
# rows the top screen renders. This is the single rule for which rows are
# INERT — the fzf `focus` skip bind hops the cursor past them, and Enter is a
# no-op on them. A row is inert when it is:
#   • a blank spacer line (between buckets, ADR 0082),
#   • the category / terminal-action divider (_CTL_DIVIDER), or
#   • a "── BUCKET ──" header (ADR 0081).
# Everything else — Profiles, a category, a terminal action — is selectable.
#
# Pure, dependency-free (so the fzf skip bind can source JUST this, not the
# whole controller, per focus). Shared with the controller so the skip bind and
# the unit tests never drift on what "inert" means.
# =============================================================================

# guided_row_inert <line> — rc 0 when the row is inert (skip it), 1 otherwise.
# Blank / whitespace-only rows and anything opening with a box-drawing dash
# (── the divider and the bucket headers both do) are inert.
guided_row_inert() {
  local line="$1"
  [[ -z "${line//[[:space:]]/}" ]] && return 0
  [[ "$line" == ─* ]] && return 0
  return 1
}
