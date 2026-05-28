#!/usr/bin/env bash
# =============================================================================
# lib/configs.sh — Host/user config loader, merger, and validator
# =============================================================================
# Loads a host or user config by name and emits the merged result of core +
# specific to stdout as JSON. Pure: no side effects beyond reading files and
# writing to stdout/stderr.
#
# Public API:
#   load_host_config <profile>
#       → 0 ok | 1 specific missing | 2 hard error | 3 reserved name
#   load_user_config <username>
#       → 0 ok | 1 specific missing | 2 hard error | 3 reserved name
#   configs_build_registry
#       → build in-memory program index from $OS_DIR/programs/
#   resolve_program <name>
#       → echoes "<cat>/<name>"; uses registry if built; 1 if not found
#   validate_program <expected> <name>       → 0 ok | 1 with stderr message
#   validate_programs <expected> <name...>   → 0 if all ok | 1 if any failed
#
# Merge rules:
#   - Arrays on both sides:  concatenate + dedupe (order preserving)
#   - Objects on both sides: deep merge (recursively)
#   - Scalars on both sides: specific wins
#   - One side null/missing: other side wins
#
# Inputs come from $OS_DIR/<kind>/<name>/config.jsonc, where <kind> is hosts
# or users. The directory name `core` is reserved.
# =============================================================================

# shellcheck source=./jsonc.sh
source "${BASH_SOURCE[0]%/*}/jsonc.sh"

readonly _CONFIGS_RESERVED_CORE="core"

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

# Shared loader. $1 = "hosts" or "users", $2 = name.
_configs_load() {
  local kind="$1" name="$2"

  if [[ -z "${OS_DIR:-}" ]]; then
    echo "configs: OS_DIR is not set" >&2
    return 2
  fi

  if [[ "$name" == "$_CONFIGS_RESERVED_CORE" ]]; then
    echo "configs: '${_CONFIGS_RESERVED_CORE}' is a reserved name" \
         "and cannot be loaded as a real ${kind%s}" >&2
    return 3
  fi

  local base="${OS_DIR}/${kind}"
  local core_file="${base}/${_CONFIGS_RESERVED_CORE}/config.jsonc"
  local specific_file="${base}/${name}/config.jsonc"
  [[ -f "$specific_file" ]] || specific_file="${base}/vm/${name}/config.jsonc"

  if [[ ! -f "$core_file" ]]; then
    echo "configs: missing ${kind} core config: ${core_file}" >&2
    return 2
  fi

  local core_json
  if ! core_json="$(_configs_parse "$core_file")"; then
    echo "configs: failed to parse ${kind} core config: ${core_file}" >&2
    return 2
  fi

  if [[ ! -f "$specific_file" ]]; then
    # Graceful: emit core only, signal via exit code.
    echo "$core_json"
    return 1
  fi

  local spec_json
  if ! spec_json="$(_configs_parse "$specific_file")"; then
    echo "configs: failed to parse ${kind} config: ${specific_file}" >&2
    return 2
  fi

  _configs_merge "$core_json" "$spec_json"
}

load_host_config() { _configs_load hosts "$1"; }
load_user_config() { _configs_load users "$1"; }

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


