#!/usr/bin/env bash
# =============================================================================
# tools/matrix.sh — Combination Matrix entry point (ADR 0046)
# =============================================================================
# The single driver for the two-tier install-combination testing. Mirrors
# vm.sh: three subcommands over the generated cell manifest.
#
#   matrix.sh gen            Emit the cell manifest (one JSON cell per line).
#   matrix.sh emit <cell-id> Materialize one cell to a VM Profile in tmpfs.
#   matrix.sh run            Install the cell(s) in a VM via the config seam.
#
# Generator/adapter logic lives in sourced lib helpers under lib/matrix/ so it
# is unit-testable without the driver. INSTALLER_DIR is the data root (defaults to the
# repo the tool ships in).
# =============================================================================
set -euo pipefail

SELF_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
INSTALLER_DIR="${INSTALLER_DIR:-$(cd "$SELF_DIR/.." && pwd)}"
export INSTALLER_DIR

# shellcheck source=../lib/matrix/cells.sh
source "$INSTALLER_DIR/lib/matrix/cells.sh"
# shellcheck source=../lib/matrix/profile.sh
source "$INSTALLER_DIR/lib/matrix/profile.sh"
# shellcheck source=../lib/matrix/run.sh
source "$INSTALLER_DIR/lib/matrix/run.sh"
# shellcheck source=../lib/matrix/driver.sh
source "$INSTALLER_DIR/lib/matrix/driver.sh"
# shellcheck source=../lib/matrix/records.sh
source "$INSTALLER_DIR/lib/matrix/records.sh"

usage() {
  cat <<'EOF'
Usage: matrix.sh <command> [args]

Commands:
  gen               Regenerate the committed matrix records: the Tier-2
                    manifest (tests/vm/matrix-manifest.jsonl) + the coverage
                    summary (tests/vm/matrix-coverage.txt). Run at wrap-up
                    after any menu/constraint change.
  emit <cell-id>    Materialize one cell to a VM Profile in tmpfs (path on
                    stdout).
  run [--smoke|--full]
                    Run the Tier-2 set in guarded parallel VMs and print a
                    summary (--smoke = pinned seeds only, default; --full =
                    whole pairwise cover). Exits non-zero on any FAIL.
  run <cell-id>     Install + boot-verify a single cell in a VM.
  smoke             Run the curated on-demand boot set (a plain single, a
                    mirror, impermanence, and an encrypted single) in guarded
                    parallel VMs. A basic-install boot smoke, distinct from
                    run --smoke's historical-bug seeds. Exits non-zero on any
                    FAIL.
EOF
}

main() {
  local cmd="${1:-}"
  [[ -n "$cmd" ]] || { usage >&2; exit 2; }
  shift
  case "$cmd" in
    gen)  matrix_records_write ;;
    emit) matrix_emit "$@" ;;
    run)
      case "${1:-}" in
        ""|--smoke|--full) matrix_run_all "$@" ;;
        *)                 matrix_run "$@" ;;
      esac ;;
    smoke) matrix_smoke ;;
    --help | -h) usage ;;
    *) usage >&2; exit 2 ;;
  esac
}

main "$@"
