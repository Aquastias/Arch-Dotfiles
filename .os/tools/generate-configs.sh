#!/usr/bin/env bash
# =============================================================================
# tools/generate-configs.sh — Per-program Config Generator CLI
# =============================================================================
# Flags:
#   --user <name>     resolve and materialize for this user
#   --dry-run         run the full pipeline, print the plan, no writes
#   --validate-only   validate manifests (+ resolve variants if --user);
#                     no plan output, no writes
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_DIR="${OS_DIR:-$(dirname "$SCRIPT_DIR")}"

# shellcheck source=../lib/configs-generator.sh
source "$OS_DIR/lib/configs-generator.sh"

usage() {
  echo "Usage: $(basename "$0") [--user <name>] [--dry-run]" \
       "[--validate-only]" >&2
  exit 2
}

USER_NAME=""
DRY_RUN=0
VALIDATE_ONLY=0
while (( $# > 0 )); do
  case "$1" in
    --user)          USER_NAME="${2:-}"; shift 2 ;;
    --dry-run)       DRY_RUN=1; shift ;;
    --validate-only) VALIDATE_ONLY=1; shift ;;
    -h|--help)       usage ;;
    *) echo "unknown flag: $1" >&2; usage ;;
  esac
done

if (( VALIDATE_ONLY == 0 )) && [[ -z "$USER_NAME" ]]; then
  usage
fi

PROGRAMS_ROOT="${PROGRAMS_ROOT:-$OS_DIR/programs}"

if (( VALIDATE_ONLY == 1 )) && [[ -z "$USER_NAME" ]]; then
  errors=0
  for manifest in "$PROGRAMS_ROOT"/*/*/configs/manifest.jsonc \
                  "$PROGRAMS_ROOT"/*/*/configs@*/manifest.jsonc; do
    [[ -f "$manifest" ]] || continue
    if ! cg_validate_manifest "$manifest"; then
      echo "manifest invalid: $manifest" >&2
      errors=1
    fi
  done
  exit "$errors"
fi

STOW_ROOT="${STOW_ROOT:-$HOME/.dotfiles/.stow/$USER_NAME}"

# Resolve variants. Slice 02 supports user-merged variants, but slice 06
# does not yet wire `load_user_config` (slice 05 owns the host/user merge
# integration). Pass empty variants for now.
resolved="$(cg_resolve_variants "$PROGRAMS_ROOT" '{}')"

while IFS=$'\t' read -r prog variant; do
  [[ -n "$prog" ]] || continue
  manifest="$PROGRAMS_ROOT/$prog/$variant/manifest.jsonc"
  if ! cg_validate_manifest "$manifest"; then
    echo "manifest invalid: $manifest" >&2
    exit 1
  fi
done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<<"$resolved")

if (( VALIDATE_ONLY == 1 )); then
  exit 0
fi

plan="$(cg_build_plan "$PROGRAMS_ROOT" "$resolved" "$STOW_ROOT")"
conflicts="$(cg_detect_conflicts "$plan" "" "")"

if [[ "$(jq 'length' <<<"$conflicts")" != "0" ]]; then
  jq -r '.[] | "conflict: \(.plan_entry.dst_in_stow_tree) ↔ \(.legacy_path)"' \
    <<<"$conflicts" >&2
  exit 1
fi

if (( DRY_RUN == 1 )); then
  jq -r '.[] | "\(.src_abs) -> \(.dst_in_stow_tree)"' <<<"$plan" | LC_ALL=C sort
  exit 0
fi

cg_materialize "$plan"
