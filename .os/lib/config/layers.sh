#!/usr/bin/env bash
# =============================================================================
# lib/config/layers.sh — JSONC parse/merge primitives + program resolution
# =============================================================================
# The shared spine under the Profile Loader (lib/config/profile.sh): JSONC
# parsing, the core+specific merge, and the program registry / contract
# validation. Pure: no side effects beyond reading files and writing to
# stdout/stderr.
#
# Public API:
#   _configs_parse <file>     → strip JSONC + jq '.'  (returns 1 if absent)
#   _configs_merge <a> <b>    → merge two JSON values per the rules below
#   configs_build_registry
#       → build in-memory program index from $OS_DIR/programs/
#   resolve_program <name>
#       → echoes "<cat>/<name>"; uses registry if built; 1 if not found
#   program_kind <name>
#       → echoes "system" | "user" | "none"; uses registry if built
#   program_names_of_kind <system|user>
#       → echoes each program name of that kind, one per line, sorted
#   validate_program <expected> <name>       → 0 ok | 1 with stderr message
#   validate_programs <expected> <name...>   → 0 if all ok | 1 if any failed
#   reconcile_user_program <name> <host_sys_prog...>          (ADR 0036)
#
# Merge rules:
#   - Arrays on both sides:  concatenate + dedupe (order preserving)
#   - Objects on both sides: deep merge (recursively)
#   - Scalars on both sides: specific wins
#   - One side null/missing: other side wins
# =============================================================================

# shellcheck source=../jsonc.sh
source "${BASH_SOURCE[0]%/*}/../jsonc.sh"

_configs_parse() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  jsonc_strip "$file" | jq '.'
}

# Merge two JSON values per the rules above.
_configs_merge() {
  jq -n --argjson a "$1" --argjson b "$2" '
    def dedup_keep_first:
      reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
    def merge(x; y):
      if   (x == null) then y
      elif (y == null) then x
      elif (x | type) == "array"  and (y | type) == "array"
        then ((x + y) | dedup_keep_first)
      elif (x | type) == "object" and (y | type) == "object"
        then reduce ((x + y) | keys_unsorted | unique[]) as $k
          ({}; .[$k] = merge(x[$k]; y[$k]))
      else y
      end;
    merge($a; $b)
  '
}

# =============================================================================
# PROGRAM RESOLUTION & VALIDATION
# =============================================================================
# Programs live at $OS_DIR/programs/<category>/<name>/. Resolution is by name
# only — the category is recovered from the path. Validation enforces the
# system-flag contract: programs referenced from a host config must have
# system: true; from a user config, system: false.

# Build two in-memory indexes, both keyed by program name:
#   _CONFIGS_REGISTRY[name]="cat/name"   — the path index
#   _CONFIGS_KIND[name]="system"|"user"  — the config.jsonc system flag
# Call once after OS_DIR is set; resolve_program and program_kind use them
# automatically. Reading the flag here is what keeps a menu render from
# re-parsing every program's config.jsonc (R22).
configs_build_registry() {
  [[ -z "${OS_DIR:-}" ]] && { echo "configs: OS_DIR is not set" >&2; return 2; }
  declare -gA _CONFIGS_REGISTRY=()
  declare -gA _CONFIGS_KIND=()
  # Explicit sentinel: `[[ -v assoc ]]` tests index 0, so it is always false for
  # an associative array — guarding on it left the fast paths below dead and
  # every lookup re-scanning the tree.
  declare -g _CONFIGS_REGISTRY_BUILT=1
  local d name cat is_sys
  for d in "${OS_DIR}/programs"/*/*; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    cat="$(basename "$(dirname "$d")")"
    _CONFIGS_REGISTRY["$name"]="${cat}/${name}"
    is_sys=false
    if [[ -f "$d/config.jsonc" ]]; then
      is_sys="$(_configs_parse "$d/config.jsonc" | jq -r '.system // false')"
    fi
    [[ "$is_sys" == "true" ]] \
      && _CONFIGS_KIND["$name"]=system \
      || _CONFIGS_KIND["$name"]=user
  done
}

# program_kind <name> → "system" | "user" | "none".
# Answers "what kind of program is this name?" for the exclusivity validator,
# both guided pickers, and the Package Resolver. Uses the registry when built
# (O(1), no re-parse); falls back to resolving + reading config.jsonc.
program_kind() {
  local name="$1"
  if [[ -n "${_CONFIGS_REGISTRY_BUILT:-}" ]]; then
    printf '%s\n' "${_CONFIGS_KIND[$name]:-none}"
    return 0
  fi
  local rel
  resolve_program "$name" >/dev/null 2>&1 || { printf 'none\n'; return 0; }
  rel="$(resolve_program "$name")"
  local cfg="${OS_DIR}/programs/${rel}/config.jsonc"
  [[ -f "$cfg" ]] || { printf 'user\n'; return 0; }
  local is_sys
  is_sys="$(_configs_parse "$cfg" | jq -r '.system // false')"
  [[ "$is_sys" == "true" ]] && printf 'system\n' || printf 'user\n'
}

# program_names_of_kind <system|user> → the program names of that kind, one
# per line, sorted. The option set behind each of the two guided pickers.
program_names_of_kind() {
  local want="$1" name
  [[ -n "${_CONFIGS_REGISTRY_BUILT:-}" ]] || configs_build_registry || return 1
  for name in "${!_CONFIGS_KIND[@]}"; do
    [[ "${_CONFIGS_KIND[$name]}" == "$want" ]] && printf '%s\n' "$name"
  done | sort
}

# Echo "<category>/<name>" for a program name. Uses registry when built (O(1));
# falls back to glob scan otherwise. Return 1 if not found.
resolve_program() {
  local name="$1"
  if [[ -n "${_CONFIGS_REGISTRY_BUILT:-}" ]]; then
    local rel="${_CONFIGS_REGISTRY[$name]:-}"
    if [[ -n "$rel" ]]; then
      printf '%s\n' "$rel"
      return 0
    fi
    return 1
  fi
  local d cat
  for d in "${OS_DIR}/programs"/*/"$name"; do
    [[ -d "$d" ]] || continue
    cat="$(basename "$(dirname "$d")")"
    printf '%s/%s\n' "$cat" "$name"
    return 0
  done
  return 1
}

# Validate one program. $1 = "true"|"false" (expected system flag), $2 = name.
# Returns 0 if program exists and its system flag matches; 1 with a stderr
# message otherwise. Pure (no exit).
validate_program() {
  local expected="$1" name="$2"
  local rel
  if ! rel="$(resolve_program "$name")"; then
    echo "configs: program '${name}' not found under" \
         "${OS_DIR}/programs/<cat>/${name}/" >&2
    return 1
  fi
  local dir="${OS_DIR}/programs/${rel}"
  [[ -f "$dir/config.jsonc" ]] || {
    echo "configs: program '${name}' missing config.jsonc at ${dir}/" >&2
    return 1
  }
  [[ -f "$dir/install.sh" ]] || {
    echo "configs: program '${name}' missing install.sh at ${dir}/" >&2
    return 1
  }
  local is_sys
  [[ "$(program_kind "$name")" == "system" ]] && is_sys=true || is_sys=false
  if [[ "$is_sys" != "$expected" ]]; then
    if [[ "$expected" == "true" ]]; then
      echo "configs: program '${name}' is referenced from a host" \
           "config but its config.jsonc has system=${is_sys}." \
           "Expected true." >&2
    else
      echo "configs: program '${name}' is referenced from a user" \
           "config but its config.jsonc has system=${is_sys}." \
           "Expected false." >&2
    fi
    return 1
  fi
  return 0
}

# reconcile_user_program <name> <host_system_program...>
# Classify a user's program reference (ADR 0036, refines ADR 0002). Echoes:
#   user  — program is system:false → install at user level (may shadow a
#           host program of the same role)
#   noop  — program is system:true AND a host already installs it → skip
# Returns 1 with an actionable stderr message when the program is system:true
# but no host installs it (a user must not trigger a root-level install), or
# when the program is not found. The system flag stays host-owned: this never
# changes a program spec. Pure (no exit).
reconcile_user_program() {
  local name="$1"; shift
  if ! resolve_program "$name" >/dev/null; then
    echo "configs: user program '${name}' not found under" \
         "${OS_DIR}/programs/<cat>/${name}/" >&2
    return 1
  fi
  local is_sys
  [[ "$(program_kind "$name")" == "system" ]] && is_sys=true || is_sys=false
  if [[ "$is_sys" != "true" ]]; then
    printf 'user\n'
    return 0
  fi
  local h
  for h in "$@"; do
    if [[ "$h" == "$name" ]]; then
      printf 'noop\n'
      return 0
    fi
  done
  echo "configs: user references system program '${name}', but no host" \
       "installs it. Declare '${name}' in a host's system_programs, or" \
       "remove it from the user." >&2
  return 1
}

# =============================================================================
# EXCLUSIVITY: A NAME IS EITHER A PROGRAM OR A PACKAGE, NEVER BOTH
# =============================================================================
# validate_package_program_exclusivity <config-json> [label]
# Aborts config load when any packages.repo.* or packages.aur.* entry resolves
# to a program directory, naming the offending path and the correct slot.
#
# This replaces the promotion rule, which rewrote such a name into
# system_programs — but only in the Guided Installer's emit path, so a
# hand-edited profile and a TUI-authored one installed differently. Rejecting
# the overlap outright makes every front-end read the same file the same way.
#
# Returns 0 when clean; 1 with one stderr message per violation otherwise.
# Pure: reads the JSON arg + the program registry, never disks.
validate_package_program_exclusivity() {
  local config="$1" label="${2:-config}"
  [[ -n "${_CONFIGS_REGISTRY_BUILT:-}" ]] || configs_build_registry || return 1

  local rc=0 slot cat name kind
  while IFS=$'\t' read -r slot cat name; do
    [[ -n "$name" ]] || continue
    kind="$(program_kind "$name")"
    [[ "$kind" == "none" ]] && continue
    if [[ "$kind" == "system" ]]; then
      echo "configs: ${label}: packages.${slot}.${cat} lists '${name}'," \
           "but '${name}' is a System Program. Declare it in" \
           "system_programs instead, or rename the package entry." >&2
    else
      echo "configs: ${label}: packages.${slot}.${cat} lists '${name}'," \
           "but '${name}' is a User Program. Declare it in a user profile's" \
           "programs instead, or rename the package entry." >&2
    fi
    rc=1
  done < <(jq -r '
    (["repo","aur"] | .[]) as $slot
    | (.packages[$slot] // {}) | to_entries[]
    | select(.value | type == "array")
    | .key as $cat | .value[]
    | select(type == "string")
    | "\($slot)\t\($cat)\t\(.)"
  ' <<<"$config" 2>/dev/null)
  return "$rc"
}

# Validate a list of programs. Returns 0 if all pass, 1 if any fail.
# All failures are reported to stderr (no early exit).
validate_programs() {
  local expected="$1"
  shift
  local rc=0 name
  for name in "$@"; do
    validate_program "$expected" "$name" || rc=1
  done
  return "$rc"
}


