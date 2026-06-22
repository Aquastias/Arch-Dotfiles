#!/usr/bin/env bash
# =============================================================================
# tools/guided-preview.sh — drive ONLY the persistent-fzf guided menu (ADR 0042)
# =============================================================================
# The safe way to do the slice-01 HITL visual gate: it launches just the single
# long-lived fzf menu (GUIDED_PERSISTENT path) and prints the resulting override
# map + chosen terminal action. It runs NONE of the install flow — no
# 01-bootstrap-zfs, no 02-wipe, no disk access — so it is safe to run on any
# machine (not only the live ISO).
#
# Use it to confirm the slice-01 feel: navigate categories → fields → values and
# back, and check that the menu NEVER flashes back to the bare terminal and the
# toolbar/header is present at every depth. Needs a real terminal (fzf wants a
# tty); piped/non-tty invocation just reports "cancelled" and exits cleanly.
#
#   bash .os/tools/guided-preview.sh
# =============================================================================
set -Eeuo pipefail

OS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export OS_DIR
# shellcheck source=lib/guided.sh
source "${OS_DIR}/lib/guided.sh"

# Seed exactly as guided_build does, then run the menu only (calling
# guided_run_persistent directly — no GUIDED_PERSISTENT flag, no guided_build).
_GUIDED_STATE="$(cfgstate_new)"
_GUIDED_DISK=""
_guided_set_identity
_guided_users_reset
_guided_seed_primary_user

if guided_run_persistent; then
  printf '\n=== chosen action: %s ===\n' "$_GUIDED_ACTION"
  printf '=== override map (no install performed) ===\n'
  _guided_effective
else
  printf '\n=== cancelled — no terminal action (or no tty) ===\n'
fi
