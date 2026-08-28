#!/usr/bin/env bash
# =============================================================================
# lib/matrix/profile.sh — Combination Matrix Cell → VM Profile synthesizer
# =============================================================================
# Materializes a matrix cell as an ephemeral VM Profile the VM Harness can run.
# The assembled Effective Config rides inline under `.install` — the config seam
# (ADR 0046) — so Tier 2 installs the exact bytes Tier 1 assembled and the
# back-end sees a menu-identical config.
#
# Tracer-bullet slice (combination-matrix/01): fixed hardware (single 40 GiB
# disk, 8 GiB RAM, 2 vCPUs) proven by tests/vm/profiles/single/plain.jsonc.
# Disk-count = Σ disk_count, the oracle-driven verify block, and the light/heavy
# timeout band land in the synthesizer slice (05).
#
# Pure: JSON in/out. Requires INSTALLER_DIR (for the assembler's Host Core).
#
# Public API:
#   matrix_cell_profile <cell>     → the VM Profile JSON for the cell
#   matrix_emit         <cell-id>  → write the profile to tmpfs, print its path
# =============================================================================

# shellcheck source=./generator.sh
declare -F matrix_all_cells >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/generator.sh"
# shellcheck source=./synth.sh
declare -F matrix_cell_synthesize >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/synth.sh"

# matrix_cell_profile <cell> — the VM Profile JSON for the cell (the synthesizer
# derives disks / verify / timeout; the assembler bakes the install config).
matrix_cell_profile() { matrix_cell_synthesize "$1"; }

# matrix_emit <cell-id> — write the cell's VM Profile to tmpfs; print the path.
matrix_emit() {
  local id="${1:-}"
  [[ -n "$id" ]] || { echo "matrix: emit requires a <cell-id>" >&2; return 2; }
  local cell
  cell="$(matrix_all_cells "${MATRIX_SEED:-0}" \
    | jq -c --arg id "$id" 'select(.id == $id)')"
  [[ -n "$cell" ]] || { echo "matrix: unknown cell-id '$id'" >&2; return 1; }
  local out
  out="$(mktemp "${TMPDIR:-/tmp}/matrix-profile.${id}.XXXXXX.jsonc")"
  matrix_cell_profile "$cell" > "$out"
  printf '%s\n' "$out"
}
