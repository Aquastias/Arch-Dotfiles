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
# Requires INSTALLER_DIR. Honors REPO_URL (passed through to the VM Harness);
# matrix.sh run --local serves local HEAD instead of the pushed repo.
#
# Public API:
#   matrix_run [<cell-id>]   → install + boot-verify the cell (default tracer)
#   matrix_run_serve_local   → REPO_URL = local HEAD, served for the run
#
# Used by: lib/matrix/driver.sh, lib/matrix/profile.sh, tools/matrix.sh.
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

  # --recreate: a cell VM is disposable; reusing a stale domain would keep its
  # old RAM/vCPU/disk size and silently ignore the overrides.
  local -a arguments=(--testing --recreate --profile "$profile")
  [[ "$bootv" == true ]] \
    && arguments=(--testing --recreate --verify-boot --profile "$profile")
  "$INSTALLER_DIR/vm/vm.sh" "${arguments[@]}"
}

# matrix_run_serve_local — stage local HEAD once and serve it for the whole
# run: parallel cells share CACHE_DIR and HTTP_PORT, so each cell's own server
# would race (the first to finish kills it mid-clone for the rest). A cell's
# server then fails to bind, harmlessly; this one outlives every cell.
matrix_run_serve_local() {
  : "${CACHE_DIR:=$INSTALLER_DIR/tests/vm/.vm-test}"
  export CACHE_DIR
  # shellcheck source=../../vm/lib/repo-source.sh
  declare -F vm_repo_source_stage_local >/dev/null 2>&1 \
    || source "$INSTALLER_DIR/vm/lib/repo-source.sh"
  REPO_URL="$(vm_repo_source_stage_local "$CACHE_DIR" local-repo.git)"
  export REPO_URL
  "$INSTALLER_DIR/vm/lib/serve-http.sh" "$CACHE_DIR" "$LIBVIRT_GATEWAY" \
    "$HTTP_PORT" >/dev/null 2>&1 &
  MATRIX_LOCAL_SERVER_PID=$!
  trap 'kill "$MATRIX_LOCAL_SERVER_PID" 2>/dev/null || true' EXIT
  echo "[matrix] serving local HEAD at $REPO_URL" >&2
}
