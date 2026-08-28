#!/usr/bin/env bash
# =============================================================================
# lib/matrix/cells.sh — Combination Matrix `gen` entry (ADR 0046)
# =============================================================================
# `matrix.sh gen` emits the committed Tier-2 Matrix Manifest — the pairwise
# cover ∪ pinned historical-bug seeds, one JSON cell per line — after asserting
# the Axis Registry classifies _MENU_FIELDS exactly. The exhaustive Tier-1 set
# is regenerated live in bats (matrix_tier1_cells), not printed here (ADR 0046:
# only the expensive Tier-2 set is committed/reviewable).
#
# The registry gate runs first, so an unclassified new menu field (or a stale
# entry) aborts the generator before any cell is emitted — the matrix can't
# silently drift from what the menu offers.
#
# Pure: JSON on stdout, no TTY, no disk writes. Requires INSTALLER_DIR (menu functions).
#
# Public API:
#   matrix_gen_cells   → the Tier-2 Matrix Manifest, one JSON cell per line
# =============================================================================

# shellcheck source=./registry.sh
declare -F matrix_registry_assert >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/registry.sh"
# shellcheck source=./generator.sh
declare -F matrix_tier2_cells >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/generator.sh"

# matrix_gen_cells — the Tier-2 Matrix Manifest on stdout (JSON cell per line).
# MATRIX_SEED pins the pairwise draw (default 0) for reproducibility.
matrix_gen_cells() {
  matrix_registry_assert || return 1
  matrix_tier2_cells "${MATRIX_SEED:-0}"
}
