#!/usr/bin/env bash
# =============================================================================
# tools/generate-configs.sh — Per-program Config Generator CLI
# =============================================================================
# Flags:
#   --user <name>     resolve and materialize for this user
#   --dry-run         run the full pipeline, print the plan, no writes
#   --validate-only   validate manifests (+ resolve variants if --user);
#                     no plan output, no writes
#
# --dry-run and --validate-only are mutually exclusive.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_DIR="${OS_DIR:-$(dirname "$SCRIPT_DIR")}"
export OS_DIR

# shellcheck source=../lib/shell-stdlib.sh
source "$OS_DIR/lib/shell-stdlib.sh"
# shellcheck source=../lib/configs-generator.sh
source "$OS_DIR/lib/configs-generator.sh"
# shellcheck source=../lib/configs.sh
source "$OS_DIR/lib/configs.sh"

usage() {
  {
    echo "Usage: $(basename "$0") [--user <name>] [--dry-run]" \
         "[--validate-only]"
    echo "  --dry-run and --validate-only are mutually exclusive."
  } >&2
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
    *) print_status error "unknown flag: $1" >&2; usage ;;
  esac
done

if (( DRY_RUN == 1 )) && (( VALIDATE_ONLY == 1 )); then
  print_status error \
    "--dry-run and --validate-only are mutually exclusive" >&2
  usage
fi

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
      print_status error "manifest invalid: $manifest" >&2
      errors=1
    fi
  done
  exit "$errors"
fi

STOW_ROOT="${STOW_ROOT:-$HOME/.dotfiles/.stow/$USER_NAME}"

# Merge users/core + users/<USER_NAME> and extract .variants (or {} if absent).
# load_user_config returns 0 when both core and specific exist, 1 when only
# core exists (still fine — empty variants), >=2 on hard error.
user_merged="$(load_user_config "$USER_NAME")" || urc=$?
urc="${urc:-0}"
if (( urc >= 2 )); then
  exit 1
fi
variants="$(jq -c '.variants // {}' <<<"$user_merged")"

resolved="$(cg_resolve_variants "$PROGRAMS_ROOT" "$variants")"

while IFS=$'\t' read -r prog variant; do
  [[ -n "$prog" ]] || continue
  manifest="$PROGRAMS_ROOT/$prog/$variant/manifest.jsonc"
  if ! cg_validate_manifest "$manifest"; then
    print_status error "manifest invalid: $manifest" >&2
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
    <<<"$conflicts" \
    | while IFS= read -r line; do print_status error "$line" >&2; done
  exit 1
fi

if (( DRY_RUN == 1 )); then
  jq -r '.[] | "\(.src_abs) -> \(.dst_in_stow_tree)"' <<<"$plan" | LC_ALL=C sort
  exit 0
fi

cg_materialize "$plan"
