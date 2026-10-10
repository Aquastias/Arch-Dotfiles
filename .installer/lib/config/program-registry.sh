#!/usr/bin/env bash
# =============================================================================
# lib/config/program-registry.sh — JSONC parse/merge + program resolution
# =============================================================================
# The shared spine under the Profile Loader (lib/config/profile-loader.sh):
# JSONC parsing, the core+specific merge, and the program registry / contract
# validation. Pure: no side effects beyond reading files and writing to
# stdout/stderr.
#
# Public API:
#   _program_registry_parse <file>  → strip JSONC + jq '.' (returns 1 if
#                                     absent)
#   _program_registry_merge <a> <b> → merge two JSON values per the rules
#                                     below
#   program_registry_build
#       → build in-memory program index from $INSTALLER_DIR/programs/
#   program_registry_resolve <name>
#       → echoes "<category>/<name>"; uses registry if built; 1 if not found
#   program_registry_kind <name>
#       → echoes "host" | "user" | "none"; uses registry if built
#   program_registry_names_of_kind <host|user>
#       → echoes each program name of that kind, one per line, sorted
#   program_registry_validate <expected> <name>
#       → 0 ok | 1 with stderr message
#   program_registry_validate_all <expected> <name...>
#       → 0 if all ok | 1 if any failed
#   program_registry_reconcile_user_program <name> <host_program...>
#       (ADR 0036)
#
# Merge rules:
#   - Arrays on both sides:  concatenate + dedupe (order preserving)
#   - Objects on both sides: deep merge (recursively)
#   - Scalars on both sides: specific wins
#   - One side null/missing: other side wins
#
# Used by: lib/config/{profile-loader,config-state,emit}.sh, 03-install.sh,
# lib/profiles/runner.sh, lib/guided/controller.sh.
# =============================================================================

# shellcheck source=../jsonc.sh
source "${BASH_SOURCE[0]%/*}/../jsonc.sh"

_program_registry_parse() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  jsonc_strip "$file" | jq '.'
}

# Merge two JSON values per the rules above.
_program_registry_merge() {
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
# Programs live at $INSTALLER_DIR/programs/<category>/<name>/. Resolution is by
# name only — the category is recovered from the path. Validation enforces the
# kind contract: programs referenced from a host config must be kind "host";
# from a user config, kind "user".

# Build two in-memory indexes, both keyed by program name:
#   _PROGRAM_REGISTRY_PATHS[name]="category/name" — the path index
#   _PROGRAM_REGISTRY_KINDS[name]="host"|"user"   — config.jsonc `kind`
# Call once after INSTALLER_DIR is set; program_registry_resolve and
# program_registry_kind use them automatically. Reading the flag here is what
# keeps a menu render from re-parsing every program's config.jsonc (R22). A
# program config with an absent or out-of-set `kind` aborts the build (return 1)
# naming the program.
program_registry_build() {
  [[ -n "${INSTALLER_DIR:-}" ]] || {
    echo "configs: INSTALLER_DIR is not set" >&2
    return 2
  }
  declare -gA _PROGRAM_REGISTRY_PATHS=()
  declare -gA _PROGRAM_REGISTRY_KINDS=()
  # Explicit sentinel: `[[ -v assoc ]]` tests index 0, so it is always false for
  # an associative array — guarding on it left the fast paths below dead and
  # every lookup re-scanning the tree.
  declare -g _PROGRAM_REGISTRY_BUILT=1
  local program_directory name category kind
  for program_directory in "${INSTALLER_DIR}/programs"/*/*; do
    [[ -d "$program_directory" ]] || continue
    name="${program_directory##*/}"
    category="${program_directory%/*}"
    category="${category##*/}"
    _PROGRAM_REGISTRY_PATHS["$name"]="${category}/${name}"
    kind=""
    [[ -f "$program_directory/config.jsonc" ]] \
      && kind="$(_program_registry_parse "$program_directory/config.jsonc" \
        | jq -r '.kind // ""')"
    case "$kind" in
      host | user) _PROGRAM_REGISTRY_KINDS["$name"]="$kind" ;;
      *) echo "configs: program '${name}' has an invalid or missing 'kind'" \
              "(want \"host\" or \"user\"), got '${kind:-<none>}' in" \
              "${program_directory}/config.jsonc" >&2
         return 1 ;;
    esac
  done
}

# program_registry_kind <name> → "host" | "user" | "none".
# Answers "what kind of program is this name?" for the exclusivity validator,
# both guided pickers, and the Package Resolver. Uses the registry when built
# (O(1), no re-parse); falls back to resolving + reading config.jsonc.
program_registry_kind() {
  local name="$1"
  if [[ -n "${_PROGRAM_REGISTRY_BUILT:-}" ]]; then
    printf '%s\n' "${_PROGRAM_REGISTRY_KINDS[$name]:-none}"
    return 0
  fi
  local relative_path
  program_registry_resolve "$name" >/dev/null 2>&1 \
    || { printf 'none\n'; return 0; }
  relative_path="$(program_registry_resolve "$name")"
  local config_file="${INSTALLER_DIR}/programs/${relative_path}/config.jsonc"
  [[ -f "$config_file" ]] || { printf 'none\n'; return 0; }
  local kind
  kind="$(_program_registry_parse "$config_file" | jq -r '.kind // ""')"
  case "$kind" in
  host | user) printf '%s\n' "$kind" ;;
  *)           printf 'none\n' ;;
  esac
}

# program_registry_names_of_kind <host|user> → the program names of that
# kind, one per line, sorted. The option set behind each of the two guided
# pickers.
program_registry_names_of_kind() {
  local want="$1" name
  [[ -n "${_PROGRAM_REGISTRY_BUILT:-}" ]] || program_registry_build || return 1
  for name in "${!_PROGRAM_REGISTRY_KINDS[@]}"; do
    [[ "${_PROGRAM_REGISTRY_KINDS[$name]}" == "$want" ]] \
      && printf '%s\n' "$name"
  done | sort
}

# Echo "<category>/<name>" for a program name. Uses registry when built (O(1));
# falls back to glob scan otherwise. Return 1 if not found.
program_registry_resolve() {
  local name="$1"
  if [[ -n "${_PROGRAM_REGISTRY_BUILT:-}" ]]; then
    local relative_path="${_PROGRAM_REGISTRY_PATHS[$name]:-}"
    if [[ -n "$relative_path" ]]; then
      printf '%s\n' "$relative_path"
      return 0
    fi
    return 1
  fi
  local program_directory category
  for program_directory in "${INSTALLER_DIR}/programs"/*/"$name"; do
    [[ -d "$program_directory" ]] || continue
    category="${program_directory%/*}"
    category="${category##*/}"
    printf '%s/%s\n' "$category" "$name"
    return 0
  done
  return 1
}

# Validate one program. $1 = "host"|"user" (expected kind), $2 = name.
# Returns 0 if program exists and its kind matches; 1 with a stderr
# message otherwise. Pure (no exit).
program_registry_validate() {
  local expected="$1" name="$2"
  local relative_path
  if ! relative_path="$(program_registry_resolve "$name")"; then
    echo "configs: program '${name}' not found under" \
         "${INSTALLER_DIR}/programs/<cat>/${name}/" >&2
    return 1
  fi
  local program_directory="${INSTALLER_DIR}/programs/${relative_path}"
  [[ -f "$program_directory/config.jsonc" ]] || {
    echo "configs: program '${name}' missing config.jsonc at" \
         "${program_directory}/" >&2
    return 1
  }
  [[ -f "$program_directory/install.sh" ]] || {
    echo "configs: program '${name}' missing install.sh at" \
         "${program_directory}/" >&2
    return 1
  }
  local got; got="$(program_registry_kind "$name")"
  if [[ "$got" != "$expected" ]]; then
    echo "configs: program '${name}' is referenced from a ${expected}" \
         "config but its config.jsonc has kind=${got}." \
         "Expected ${expected}." >&2
    return 1
  fi
  return 0
}

# program_registry_reconcile_user_program <name> <host_program...>
# Classify a user's program reference (ADR 0036, refines ADR 0002). Echoes:
#   user  — program is kind user → install at user level (may shadow a
#           host program of the same role)
#   noop  — program is kind host AND a host already installs it → skip
# Returns 1 with an actionable stderr message when the program is kind host
# but no host installs it (a user must not trigger a root-level install), or
# when the program is not found. The kind stays host-owned: this never
# changes a program spec. Pure (no exit).
program_registry_reconcile_user_program() {
  local name="$1"; shift
  if ! program_registry_resolve "$name" >/dev/null; then
    echo "configs: user program '${name}' not found under" \
         "${INSTALLER_DIR}/programs/<cat>/${name}/" >&2
    return 1
  fi
  local is_host=false
  [[ "$(program_registry_kind "$name")" == "host" ]] && is_host=true
  if [[ "$is_host" != "true" ]]; then
    printf 'user\n'
    return 0
  fi
  local host_program
  for host_program in "$@"; do
    if [[ "$host_program" == "$name" ]]; then
      printf 'noop\n'
      return 0
    fi
  done
  echo "configs: user references Host Program '${name}', but no host" \
       "installs it. Declare '${name}' in a host's host_programs, or" \
       "remove it from the user." >&2
  return 1
}

# =============================================================================
# EXCLUSIVITY: A NAME IS EITHER A PROGRAM OR A PACKAGE, NEVER BOTH
# =============================================================================
# program_registry_validate_package_exclusivity <config-json> [label]
# Aborts config load when any packages.repo.* or packages.aur.* entry resolves
# to a program directory, naming the offending path and the correct slot.
#
# This replaces the promotion rule, which rewrote such a name into
# host_programs — but only in the Guided Installer's emit path, so a
# hand-edited profile and a TUI-authored one installed differently. Rejecting
# the overlap outright makes every front-end read the same file the same way.
#
# Returns 0 when clean; 1 with one stderr message per violation otherwise.
# Pure: reads the JSON arg + the program registry, never disks.
program_registry_validate_package_exclusivity() {
  local config="$1" label="${2:-config}"
  [[ -n "${_PROGRAM_REGISTRY_BUILT:-}" ]] || program_registry_build || return 1

  local rc=0 slot category name kind
  while IFS=$'\t' read -r slot category name; do
    [[ -n "$name" ]] || continue
    kind="$(program_registry_kind "$name")"
    [[ "$kind" == "none" ]] && continue
    if [[ "$kind" == "host" ]]; then
      echo "configs: ${label}: packages.${slot}.${category} lists '${name}'," \
           "but '${name}' is a Host Program. Declare it in" \
           "host_programs instead, or rename the package entry." >&2
    else
      echo "configs: ${label}: packages.${slot}.${category} lists '${name}'," \
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
program_registry_validate_all() {
  local expected="$1"
  shift
  local rc=0 name
  for name in "$@"; do
    program_registry_validate "$expected" "$name" || rc=1
  done
  return "$rc"
}


