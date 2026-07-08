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
# Pure: JSON in/out. Requires OS_DIR (for the assembler's Host Core).
#
# Public API:
#   matrix_cell_profile <cell>     → the VM Profile JSON for the cell
#   matrix_emit         <cell-id>  → write the profile to tmpfs, print its path
# =============================================================================

# shellcheck source=./generator.sh
[[ "$(type -t matrix_all_cells)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/generator.sh"
# shellcheck source=./assemble.sh
[[ "$(type -t matrix_cell_assemble)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/assemble.sh"

# matrix_cell_profile <cell> — the VM Profile JSON for the cell.
matrix_cell_profile() {
  local cell="$1" name eff
  name="matrix-$(jq -r '.id' <<<"$cell")"
  eff="$(matrix_cell_assemble "$cell")"
  jq -n --arg name "$name" --argjson install "$eff" '{
    name: $name,
    hardware: { disks: [40], ram_mb: 8192, vcpus: 2 },
    install: $install
  }'
}

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
