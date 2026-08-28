#!/usr/bin/env bash
# Prints the resolved package set for a profile, grouped by source, so
# "what actually lands on this machine?" is answerable without launching the
# installer.
#
# Usage: explain-packages.sh <profile> [--flat|--sources]
#   <profile>   a hosts/<name>/ directory (desktop, laptop, arch-kde, …)
#   --flat      one package per line, sorted, no grouping (pipe-friendly)
#   --sources   just the source names and their counts
#
# Works on a HAND-EDITED profile with no TUI involvement — that is the whole
# point. It calls the same Package Resolver as the menu's read-only derived
# section, so the two cannot drift.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_DIR="$(dirname "$SCRIPT_DIR")"
export OS_DIR

# shellcheck source=../lib/common.sh
source "${OS_DIR}/lib/common.sh"
# shellcheck source=../lib/config/profile.sh
source "${OS_DIR}/lib/config/profile.sh"
# shellcheck source=../lib/packages/resolver.sh
source "${OS_DIR}/lib/packages/resolver.sh"

profile="${1:-}"
mode="${2:-grouped}"

if [[ -z "$profile" || "$profile" == "-h" || "$profile" == "--help" ]]; then
  sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's|^# \{0,1\}||'
  echo
  echo "Available profiles:"
  for d in "${OS_DIR}"/hosts/*/ "${OS_DIR}"/hosts/vm/*/; do
    [[ -f "${d}profile.jsonc" ]] || continue
    n="$(basename "$d")"; [[ "$n" == "core" ]] && continue
    printf '  - %s\n' "$n"
  done
  exit 0
fi

# Resolve the profile over Host Core through the Layer Resolver — the same
# path install.sh --profile takes, so the report matches the install.
if ! effective="$(load_profile "$profile" 2>/dev/null)"; then
  rc=$?
  if [[ $rc -eq 1 ]]; then
    echo "explain-packages: no profile '${profile}' — resolved core only." >&2
  else
    echo "explain-packages: could not load profile '${profile}'." >&2
    exit 1
  fi
fi

resolved="$(pkgres_resolve "$effective")"
unresolved="$(pkgres_unresolved "$effective")"

# Exclusions are read from the AUTHORED profile, not the resolved one: the
# Layer Resolver applies packages.exclude and then strips the key, so by the
# time a config is resolved there is nothing left to report. Reading the
# committed file is what lets the operator confirm an exclusion took effect.
authored="$(jsonc_strip "${OS_DIR}/hosts/${profile}/profile.jsonc" 2>/dev/null \
  || jsonc_strip "${OS_DIR}/hosts/vm/${profile}/profile.jsonc" 2>/dev/null \
  || printf '{}')"
excluded="$(pkgres_excluded "$authored")"

case "$mode" in
--flat)
  cut -f3 <<<"$resolved" | sort -u
  exit 0
  ;;
--sources)
  cut -f1 <<<"$resolved" | sort | uniq -c \
    | awk '{ printf "  %-18s %s\n", $2, $1 }'
  exit 0
  ;;
esac

printf '\n  Resolved package set — profile: %s\n' "$profile"
printf '  %s\n\n' "$(printf '─%.0s' {1..60})"

# Group by source, in the resolver's declared order, so the report reads the
# same way every time.
while IFS= read -r src; do
  pkgs="$(awk -F'\t' -v s="$src" '$1 == s { print $3 }' <<<"$resolved" \
    | sort -u)"
  [[ -n "$pkgs" ]] || continue
  layer="$(awk -F'\t' -v s="$src" '$1 == s { print $2 }' <<<"$resolved" \
    | sort -u | paste -sd'+' -)"
  printf '  %s  (%s, %d)\n' "$src" "$layer" "$(wc -l <<<"$pkgs")"
  fmt -w 68 <<<"$pkgs" | tr '\n' ' ' | fold -s -w 68 \
    | sed 's/^/      /' | sed 's/[[:space:]]*$//'
  printf '\n'
done < <(pkgres_sources)

total="$(cut -f3 <<<"$resolved" | sort -u | wc -l)"
printf '  %s\n' "$(printf '─%.0s' {1..60})"
printf '  Total: %d unique packages\n' "$total"

if [[ -n "$excluded" ]]; then
  printf '\n  Excluded by this profile (%d):\n' "$(wc -l <<<"$excluded")"
  sed 's/^/      /' <<<"$excluded"
fi

if [[ -n "$unresolved" ]]; then
  printf '\n  Resolved at install time (needs the target hardware):\n'
  sed 's/^/      /' <<<"$unresolved"
fi
printf '\n'
