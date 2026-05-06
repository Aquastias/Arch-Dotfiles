#!/usr/bin/env bash
# =============================================================================
# lib/configs.sh — Host/user config loader and merger
# =============================================================================
# Loads a host or user config by name and emits the merged result of core +
# specific to stdout as JSON. Pure: no side effects beyond reading files and
# writing to stdout/stderr.
#
# Public API:
#   load_host_config <hostname>   → 0 ok | 1 specific missing | 2 hard error | 3 reserved name
#   load_user_config <username>   → 0 ok | 1 specific missing | 2 hard error | 3 reserved name
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

readonly _CONFIGS_RESERVED_CORE="core"

# Strip JSONC // comments and emit JSON on stdout.
_configs_strip_comments() {
  sed \
    -e 's|[[:space:]]*//$||' \
    -e 's|[[:space:]]//[^"]*$||' \
    -e '/^[[:space:]]*\/\//d' \
    "$1" 2>/dev/null
}

_configs_parse() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  _configs_strip_comments "$file" | jq '.'
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
        then reduce ((x + y) | keys_unsorted | unique[]) as $k ({}; .[$k] = merge(x[$k]; y[$k]))
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
    echo "configs: '${_CONFIGS_RESERVED_CORE}' is a reserved name and cannot be loaded as a real ${kind%s}" >&2
    return 3
  fi

  local base="${OS_DIR}/${kind}"
  local core_file="${base}/${_CONFIGS_RESERVED_CORE}/config.jsonc"
  local specific_file="${base}/${name}/config.jsonc"

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
