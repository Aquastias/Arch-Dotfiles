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

# Build an in-memory index: _CONFIGS_REGISTRY[name]="cat/name".
# Call once after OS_DIR is set; resolve_program uses it automatically.
configs_build_registry() {
  [[ -z "${OS_DIR:-}" ]] && { echo "configs: OS_DIR is not set" >&2; return 2; }
  declare -gA _CONFIGS_REGISTRY=()
  local d name cat
  for d in "${OS_DIR}/programs"/*/*; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    cat="$(basename "$(dirname "$d")")"
    _CONFIGS_REGISTRY["$name"]="${cat}/${name}"
  done
}

# Echo "<category>/<name>" for a program name. Uses registry when built (O(1));
# falls back to glob scan otherwise. Return 1 if not found.
resolve_program() {
  local name="$1"
  if [[ -v _CONFIGS_REGISTRY ]]; then
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
  is_sys="$(_configs_parse "$dir/config.jsonc" | jq -r '.system')"
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
  local rel
  if ! rel="$(resolve_program "$name")"; then
    echo "configs: user program '${name}' not found under" \
         "${OS_DIR}/programs/<cat>/${name}/" >&2
    return 1
  fi
  local is_sys
  is_sys="$(_configs_parse "${OS_DIR}/programs/${rel}/config.jsonc" \
    | jq -r '.system')"
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


