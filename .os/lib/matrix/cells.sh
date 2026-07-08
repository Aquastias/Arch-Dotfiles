#!/usr/bin/env bash
# =============================================================================
# lib/matrix/cells.sh — Combination Matrix Cell Generator (ADR 0046)
# =============================================================================
# Emits the matrix's cells as JSON lines — one cell per line, each a stable
# cell-id plus its axis assignment. A cell is the menu-reachable combination of
# storage/install axes the two tiers check. Axes are (will be) derived from the
# menu's own option functions so the manifest can't drift from what the menu
# offers.
#
# Tracer-bullet slice (combination-matrix/01): the generator emits the single
# simplest cell — zfs root, single disk, unencrypted, no desktop. Axis fan-out,
# the pairwise cover, and seeds arrive in later slices; this establishes the
# JSON-lines contract every later slice extends.
#
# Pure: JSON on stdout, no TTY, no disk writes.
#
# Public API:
#   matrix_gen_cells   → the matrix manifest, one JSON cell per line
# =============================================================================

# matrix_gen_cells — the matrix manifest on stdout (one JSON cell per line).
matrix_gen_cells() {
  jq -c -n '{
    id: "zfs-single-plain",
    axes: {
      filesystem:   "zfs",
      topology:     "single",
      encryption:   false,
      impermanence: false,
      desktop:      []
    }
  }'
}
