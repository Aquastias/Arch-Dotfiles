#!/usr/bin/env bash
# =============================================================================
# tools/feature-audit.sh — Feature Audit entry point (ADR 0152)
# =============================================================================
# Installs the max-feature base + Audit Variants one VM at a time, collects
# every error-shaped signal from install to the final upgrade reboot, and
# judges it into Findings. Manual only (multi-hour, needs libvirt).
#
#   feature-audit.sh check             Manifest + coverage, no VM.
#   feature-audit.sh run [opts]        Live Audit Run (runs check first).
#   feature-audit.sh report <run-dir>  Raw artifacts → Findings, no VM.
#
# Logic lives in lib/feature-audit/ so it is unit-testable without the driver.
# =============================================================================
set -euo pipefail

SELF_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
INSTALLER_DIR="${INSTALLER_DIR:-$(cd "$SELF_DIR/.." && pwd)}"
export INSTALLER_DIR

# shellcheck source=../lib/jsonc.sh
source "$INSTALLER_DIR/lib/jsonc.sh"
# shellcheck source=../lib/feature-audit/report.sh
source "$INSTALLER_DIR/lib/feature-audit/report.sh"
# shellcheck source=../lib/feature-audit/binds.sh
source "$INSTALLER_DIR/lib/feature-audit/binds.sh"
# shellcheck source=../lib/feature-audit/check.sh
source "$INSTALLER_DIR/lib/feature-audit/check.sh"
# shellcheck source=../lib/feature-audit/manifest.sh
source "$INSTALLER_DIR/lib/feature-audit/manifest.sh"

usage() {
  cat <<'EOF2'
Usage: feature-audit.sh <command> [args]

Commands:
  check             Manifest + coverage checks, no VM: one Finding per
                    line, exit 1 on any.
  run [--variant X | --from X] [--keep]
                    Live Audit Run: install each Audit Variant in turn
                    (one VM), collect, then report into
                    .installer/.audit-runs/<ts>/. --variant runs one,
                    --from resumes at one, --keep holds the last VM.
                    Needs libvirt (run with the sandbox off).
  report <run-dir>  Judge a run folder's raw artifacts into Findings:
                    writes findings.md + findings.jsonl there. Exit 1 on
                    any Finding, 2 on usage error.
EOF2
}

main() {
  local cmd="${1:-}"
  [[ -n "$cmd" ]] || { usage >&2; exit 2; }
  shift
  case "$cmd" in
    run)
      # shellcheck source=../lib/feature-audit/live.sh
      source "$INSTALLER_DIR/lib/feature-audit/live.sh"
      fa_run "$@" ;;
    check) fa_check ;;
    report)
      [[ $# -eq 1 ]] || { usage >&2; exit 2; }
      fa_report "$1" ;;
    --help | -h) usage ;;
    *) usage >&2; exit 2 ;;
  esac
}

main "$@"
