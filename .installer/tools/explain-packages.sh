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
INSTALLER_DIR="$(dirname "$SCRIPT_DIR")"
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
      explain_package_names "$resolved"
      return 0 ;;
    --sources)
      explain_source_counts "$resolved"
      return 0 ;;
  esac
  explain_report "$profile" "$resolved" "$excluded" "$unresolved"
}

# explain_usage — the header comment as help, then the available profiles.
explain_usage() {
  local line
  # Lines 2-14 of this file: the header comment.
  while IFS= read -r line; do
    # Without the leading "# " (or a bare "#").
    if [[ "$line" == "# "* ]]; then printf '%s\n' "${line:2}"
    else printf '%s\n' "${line:1}"; fi
  done < <(head -n 14 "${BASH_SOURCE[0]}" | tail -n +2)
  echo
  echo "Available profiles:"
  local directory name
  for directory in "${INSTALLER_DIR}"/hosts/*/ \
                   "${INSTALLER_DIR}"/hosts/vm/*/; do
    [[ -f "${directory}profile.jsonc" ]] || continue
    name="$(basename "$directory")"
    profile_loader_is_layer hosts "$name" && continue
    printf '  - %s\n' "$name"
  done
  return 0
}

# explain_load_profile <profile> — the profile resolved over its layers (Host
# Core, plus the Fleet Layer for a fleet host) through the Layer Resolver —
# the same path install.sh --profile takes, so the report matches the install.
# A profile with no file resolves Host Core alone (the loader's status 1),
# reported on stderr.
explain_load_profile() {
  local profile="$1" effective status=0
  effective="$(profile_loader_load "$profile" 2>/dev/null)" || status=$?
  case "$status" in
    0) ;;
    1) echo "explain-packages: no profile '${profile}' — resolved core" \
         "only." >&2 ;;
    *) echo "explain-packages: could not load profile '${profile}'." >&2
       return 1 ;;
  esac
  printf '%s\n' "$effective"
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
  local count source_name sources
  sources="$(printf '%s\n' "$1" | cut -f1)"
  while read -r count source_name; do
    printf '  %-18s %s\n' "$source_name" "$count"
  # Each source's row count, by source name.
  done < <(printf '%s\n' "$sources" | sort | uniq -c)
}

# explain_package_names <resolved> — the package names (column 3), sorted,
# each once.
explain_package_names() {
  # Column 3 of every row, each value once.
  printf '%s\n' "$1" | cut -f3 | sort -u
}

# explain_indented <lines> — each line, indented six spaces.
explain_indented() {
  local line
  while IFS= read -r line; do printf '      %s\n' "$line"
  done < <(printf '%s\n' "$1")
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
  # How many distinct packages.
  total="$(explain_package_names "$resolved" | wc -l)"
  printf '  %s\n' "$rule"
  printf '  Total: %d unique packages\n' "$total"

  if [[ -n "$excluded" ]]; then
    printf '\n  Excluded by this profile (%d):\n' \
      "$(printf '%s\n' "$excluded" | wc -l)"
    explain_indented "$excluded"
  fi
  if [[ -n "$unresolved" ]]; then
    printf '\n  Resolved at install time (needs the target hardware):\n'
    explain_indented "$unresolved"
  fi
  printf '\n'
}

# explain_source_group <source> <resolved> — one source's heading (its
# layers and count) and its packages wrapped to 68 columns; nothing when
# the source contributed no package.
explain_source_group() {
  local source_name="$1" resolved="$2" layers row_source layer package
  local source_layers="" source_packages=""
  local -a packages
  # This source's rows: their layers and packages.
  while IFS=$'\t' read -r row_source layer package; do
    [[ "$row_source" == "$source_name" ]] || continue
    source_layers+="${layer}"$'\n'
    source_packages+="${package}"$'\n'
  done < <(printf '%s\n' "$resolved")
  # The packages, sorted, each once.
  mapfile -t packages < <(printf '%s' "$source_packages" | sort -u)
  ((${#packages[@]})) || return 0
  # The layers, sorted, each once, "+"-joined.
  layers="$(printf '%s' "$source_layers" | sort -u | paste -sd+ -)"
  printf '  %s  (%s, %d)\n' "$source_name" "$layers" "${#packages[@]}"
  printf '%s\n' "${packages[@]}" \
    | awk -v width=68 -f "${INSTALLER_DIR}/tools/explain-wrap.awk"
  printf '\n'
}

main "$@"
