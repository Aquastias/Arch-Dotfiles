#!/usr/bin/env bash
# =============================================================================
# lib/matrix/run.sh — Combination Matrix Tier-2 driver (ADR 0046)
# =============================================================================
# Installs matrix cell(s) in a real VM through the config seam: emit the cell's
# VM Profile to tmpfs, then hand it to the VM Harness (vm.sh --testing), which
# installs the inline Effective Config and — with --verify-boot — power-cycles
# to prove first boot.
#
# Tracer-bullet slice (combination-matrix/01): drive the single tracer cell end
# to end. The host-resource guard, 3-way parallel scheduling, per-cell oracle
# dispatch, and the run-all summary table land in slice 06.
#
# Requires INSTALLER_DIR. Honors REPO_URL (passed through to the VM Harness).
#
# Public API:
#   matrix_run [<cell-id>]   → install + boot-verify the cell (default tracer)
# =============================================================================

# shellcheck source=./profile.sh
declare -F matrix_emit >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/profile.sh"

# matrix_run [<cell-id>] — emit the cell's profile and run it through the VM
# Harness. The oracle decides boot verification: plain/impermanent AND encrypted
# cells power-cycle (--verify-boot) — the Console Answerer unlocks encrypted
# roots over serial (matrix issue 07); only gpu≠auto cells run install-only
# (INSTALLER-EXIT-0 is the whole oracle). Defaults to the tracer cell.
matrix_run() {
  local id="${1:-zfs-single-plain}"
  local cell profile bootv
  cell="$(matrix_all_cells "${MATRIX_SEED:-0}" \
    | jq -c --arg id "$id" 'select(.id == $id)')"
  [[ -n "$cell" ]] || { echo "matrix: unknown cell-id '$id'" >&2; return 1; }
  bootv="$(matrix_cell_boot_verify "$cell")"

  profile="$(matrix_emit "$id")" || return $?
  echo "[matrix] cell '$id' → profile $profile (boot-verify=$bootv)" >&2

  local -a args=(--testing --profile "$profile")
  [[ "$bootv" == true ]] && args=(--testing --verify-boot --profile "$profile")
  "$INSTALLER_DIR/vm/vm.sh" "${args[@]}"
}
