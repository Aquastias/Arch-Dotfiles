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
# is unit-testable without the driver. OS_DIR is the data root (defaults to the
# repo the tool ships in).
# =============================================================================
set -euo pipefail

SELF_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
OS_DIR="${OS_DIR:-$(cd "$SELF_DIR/.." && pwd)}"
export OS_DIR

# shellcheck source=../lib/matrix/cells.sh
source "$OS_DIR/lib/matrix/cells.sh"
# shellcheck source=../lib/matrix/profile.sh
source "$OS_DIR/lib/matrix/profile.sh"
# shellcheck source=../lib/matrix/run.sh
source "$OS_DIR/lib/matrix/run.sh"

usage() {
  cat <<'EOF'
Usage: matrix.sh <command> [args]

Commands:
  gen               Emit the cell manifest (one JSON cell per line).
  emit <cell-id>    Materialize one cell to a VM Profile in tmpfs (path on
                    stdout).
  run               Install the cell(s) in a VM via the config seam.
EOF
}

main() {
  local cmd="${1:-}"
  [[ -n "$cmd" ]] || { usage >&2; exit 2; }
  shift
  case "$cmd" in
    gen)  matrix_gen_cells ;;
    emit) matrix_emit "$@" ;;
    run)  matrix_run "$@" ;;
    --help | -h) usage ;;
    *) usage >&2; exit 2 ;;
  esac
}

main "$@"
