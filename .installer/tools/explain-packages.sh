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

script_path="${BASH_SOURCE[0]}"
[[ "$script_path" == */* ]] || script_path="./$script_path"
SCRIPT_DIR="$(cd "${script_path%/*}" && pwd)"
INSTALLER_DIR="${SCRIPT_DIR%/*}"
export INSTALLER_DIR

# shellcheck source=../lib/common.sh
source "${INSTALLER_DIR}/lib/common.sh"
# shellcheck source=../lib/config/profile-loader.sh
source "${INSTALLER_DIR}/lib/config/profile-loader.sh"
# shellcheck source=../lib/packages/package-resolver.sh
source "${INSTALLER_DIR}/lib/packages/package-resolver.sh"

main() {
  local profile="${1:-}" mode="${2:-grouped}"
  if [[ -z "$profile" || "$profile" == "-h" || "$profile" == "--help" ]]; then
    explain_usage
    return 0
  fi

  local effective resolved unresolved excluded
  effective="$(explain_load_profile "$profile")" || exit 1
  resolved="$(package_resolver_resolve "$effective")"
  unresolved="$(package_resolver_unresolved "$effective")"
  excluded="$(package_resolver_excluded \
    "$(explain_authored_profile "$profile")")"

  case "$mode" in
    --flat)
      awk -F'\t' '{ print $3 }' <<<"$resolved" | sort -u
      return 0 ;;
    --sources)
      explain_source_counts "$resolved"
      return 0 ;;
  esac
  explain_report "$profile" "$resolved" "$excluded" "$unresolved"
}

# explain_usage — the header comment as help, then the available profiles.
explain_usage() {
  awk 'NR >= 2 && NR <= 14 { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
  echo
  echo "Available profiles:"
  local directory name
  for directory in "${INSTALLER_DIR}"/hosts/*/ \
                   "${INSTALLER_DIR}"/hosts/vm/*/; do
    [[ -f "${directory}profile.jsonc" ]] || continue
    name="$(base_name "$directory")"
    [[ "$name" == "core" ]] && continue
    printf '  - %s\n' "$name"
  done
  return 0
}

# explain_load_profile <profile> — the profile resolved over Host Core
# through the Layer Resolver — the same path install.sh --profile takes, so
# the report matches the install.
explain_load_profile() {
  local profile="$1" effective
  if effective="$(profile_loader_load "$profile" 2>/dev/null)"; then
    printf '%s\n' "$effective"
    return 0
  fi
  echo "explain-packages: could not load profile '${profile}'." >&2
  return 1
}

# explain_authored_profile <profile> — the AUTHORED profile, not the resolved
# one: the Layer Resolver applies packages.exclude and then strips the key,
# so by the time a config is resolved there is nothing left to report.
# Reading the committed file is what lets the operator confirm an exclusion
# took effect.
explain_authored_profile() {
  local profile="$1"
  jsonc_strip "${INSTALLER_DIR}/hosts/${profile}/profile.jsonc" 2>/dev/null \
    || jsonc_strip "${INSTALLER_DIR}/hosts/vm/${profile}/profile.jsonc" \
         2>/dev/null \
    || printf '{}'
}

# explain_source_counts <resolved> — each source name and its package count,
# sorted by name.
explain_source_counts() {
  awk -F'\t' '{ print $1 }' <<<"$1" | sort | awk '
    !($0 in count) { order[++sources] = $0 }
    { count[$0]++ }
    END {
      for (i = 1; i <= sources; i++)
        printf "  %-18s %s\n", order[i], count[order[i]]
    }'
}

# explain_report <profile> <resolved> <excluded> <unresolved> — the grouped
# report: each source in the resolver's declared order (so it reads the same
# way every time), the total, then exclusions and install-time leftovers.
explain_report() {
  local profile="$1" resolved="$2" excluded="$3" unresolved="$4" rule
  rule="$(printf '─%.0s' {1..60})"
  printf '\n  Resolved package set — profile: %s\n' "$profile"
  printf '  %s\n\n' "$rule"

  local source_name
  while IFS= read -r source_name; do
    explain_source_group "$source_name" "$resolved"
  done < <(package_resolver_sources)

  local total
  total="$(awk -F'\t' '{ print $3 }' <<<"$resolved" | sort -u \
    | awk 'END { print NR }')"
  printf '  %s\n' "$rule"
  printf '  Total: %d unique packages\n' "$total"

  if [[ -n "$excluded" ]]; then
    printf '\n  Excluded by this profile (%d):\n' \
      "$(awk 'END { print NR }' <<<"$excluded")"
    printf '%s\n' "      ${excluded//$'\n'/$'\n'      }"
  fi
  if [[ -n "$unresolved" ]]; then
    printf '\n  Resolved at install time (needs the target hardware):\n'
    printf '%s\n' "      ${unresolved//$'\n'/$'\n'      }"
  fi
  printf '\n'
}

# explain_source_group <source> <resolved> — one source's heading (its
# layers and count) and its packages wrapped to 68 columns; nothing when
# the source contributed no package.
explain_source_group() {
  local source_name="$1" resolved="$2" layers
  local -a packages
  mapfile -t packages < <(awk -F'\t' -v source_name="$source_name" \
    '$1 == source_name { print $3 }' <<<"$resolved" | sort -u)
  ((${#packages[@]})) || return 0
  layers="$(awk -F'\t' -v source_name="$source_name" \
    '$1 == source_name { print $2 }' <<<"$resolved" | sort -u \
    | awk '{ joined = joined (NR > 1 ? "+" : "") $0 } END { print joined }')"
  printf '  %s  (%s, %d)\n' "$source_name" "$layers" "${#packages[@]}"
  printf '%s\n' "${packages[@]}" | awk -v width=68 '
    line != "" && length(line) + length($0) + 1 > width {
      sub(/[[:space:]]+$/, "", line); printf "%s      %s", separator, line
      separator = "\n"; line = ""
    }
    { line = line $0 " " }
    END {
      sub(/[[:space:]]+$/, "", line); printf "%s      %s", separator, line
    }'
  printf '\n'
}

main "$@"
