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
LEGACY_ROOT="${LEGACY_ROOT:-$HOME/.dotfiles}"

# Merge users/core + users/<USER_NAME>. Extract variants and declared user
# programs. load_user_config returns 0 (both exist), 1 (core only, fine for
# variants={} and programs=[]), >=2 on hard error.
user_progs_json='[]'
variants='{}'
if [[ -f "$OS_DIR/users/core/config.jsonc" ]]; then
  urc=0
  user_merged="$(load_user_config "$USER_NAME")" || urc=$?
  if (( urc >= 2 )); then
    exit 1
  fi
  variants="$(jq -c '.variants // {}' <<<"$user_merged")"
  user_progs_json="$(jq -c '.programs // []' <<<"$user_merged")"
fi

# Merge hosts/core + hosts/<hostname>. Extract system_programs declared for
# this machine. Missing hosts/core is tolerated (no system programs).
sys_progs_json='[]'
if [[ -f "$OS_DIR/hosts/core/config.jsonc" ]]; then
  hostname_now="$(hostname 2>/dev/null || printf '%s' "${HOSTNAME:-}")"
  hrc=0
  host_merged="$(load_host_config "$hostname_now")" || hrc=$?
  if (( hrc >= 2 )); then
    exit 1
  fi
  sys_progs_json="$(jq -c '.system_programs // []' <<<"$host_merged")"
fi

declared_progs_json="$(jq -c -n \
  --argjson u "$user_progs_json" \
  --argjson s "$sys_progs_json" \
  '($u + $s) | unique')"

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

plan="$(cg_build_plan "$PROGRAMS_ROOT" "$resolved" "$STOW_ROOT" \
  "$declared_progs_json")"
conflicts="$(cg_detect_conflicts "$plan" "$LEGACY_ROOT" "$STOW_ROOT")"

if [[ "$(jq 'length' <<<"$conflicts")" != "0" ]]; then
  jq -r '.[] | "conflict: \(.plan_src) ↔ \(.legacy_src) (target: \(.target))"' \
    <<<"$conflicts" \
    | while IFS= read -r line; do print_status error "$line" >&2; done
  exit 1
fi

if (( DRY_RUN == 1 )); then
  jq -r '.[] | "\(.src_abs) -> \(.dst_in_stow_tree)"' <<<"$plan"
  exit 0
fi

cg_materialize "$plan"
