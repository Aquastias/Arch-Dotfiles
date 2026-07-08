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
# Requires OS_DIR. Honors REPO_URL (passed through to the VM Harness).
#
# Public API:
#   matrix_run [<cell-id>]   → install + boot-verify the cell (default tracer)
# =============================================================================

# shellcheck source=./profile.sh
[[ "$(type -t matrix_emit)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/profile.sh"

# matrix_run [<cell-id>] — emit the cell's profile and run it through the VM
# Harness with boot verification. Defaults to the tracer cell.
matrix_run() {
  local id="${1:-zfs-single-plain}"
  local profile
  profile="$(matrix_emit "$id")" || return $?
  echo "[matrix] cell '$id' → profile $profile" >&2
  "$OS_DIR/vm/vm.sh" --testing --verify-boot --profile "$profile"
}
