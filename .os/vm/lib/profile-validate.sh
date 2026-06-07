#!/usr/bin/env bash
# =============================================================================
# vm/lib/profile-validate.sh — VM Profile schema validation (deep, pure)
# =============================================================================
# Full schema validation of a JSONC VM Profile (already stripped to JSON by the
# caller), mirroring lib/config/validation.sh's fail-fast scope. Returns 0
# silently on a valid profile, or non-zero with a human-readable message on
# stderr. Called by vm/vm.sh before any work. No libvirt, no TTY.
#
# Sourced by vm/vm.sh and tests/vm/profile-validate.bats.
# =============================================================================

# _profile_validate_int <profile> <jq_path> <min> <max> <label> required|optional
#   Asserts the value at <jq_path> is an integer in [min,max]. When `optional`,
#   an absent value passes; when `required`, an absent value is rejected.
_profile_validate_int() {
  local profile="$1" path="$2" min="$3" max="$4" label="$5" req="$6" verdict
  verdict="$(jq -r --argjson lo "$min" --argjson hi "$max" "
    ($path) as \$v
    | if   \$v == null              then \"absent\"
      elif (\$v | type) != \"number\"
           or \$v != (\$v | floor)
           or \$v < \$lo or \$v > \$hi then \"bad\"
      else \"ok\" end" <<<"$profile")"
  if [[ "$verdict" == "absent" ]]; then
    [[ "$req" == required ]] || return 0
    echo "profile: $label is required" >&2
    return 1
  fi
  [[ "$verdict" == "ok" ]] || {
    echo "profile: $label must be an integer in [$min, $max]" >&2
    return 1
  }
}

# profile_validate <profile_json> <hosts_dir>
profile_validate() {
  local profile="$1" hosts_dir="$2"

  local name
  name="$(jq -r '.name // empty' <<<"$profile")"
  [[ -n "$name" ]] || { echo "profile: missing 'name'" >&2; return 1; }

  local disks_check
  disks_check="$(jq -r '
    if   (.hardware.disks | type) != "array"      then "type"
    elif (.hardware.disks | length) == 0          then "empty"
    elif any(.hardware.disks[];
             (type != "number") or (. != floor) or (. <= 0)) then "int"
    else "ok" end' <<<"$profile")"
  [[ "$disks_check" == "ok" ]] || {
    echo "profile: hardware.disks must be a non-empty array of positive" \
         "integers (GiB)" >&2
    return 1
  }

  _profile_validate_int "$profile" '.hardware.ram_mb' 256 262144 \
    hardware.ram_mb required || return 1
  _profile_validate_int "$profile" '.hardware.vcpus' 1 256 \
    hardware.vcpus required || return 1
  _profile_validate_int "$profile" '.timeouts.install' 1 86400 \
    timeouts.install optional || return 1
  _profile_validate_int "$profile" '.timeouts.boot' 1 86400 \
    timeouts.boot optional || return 1

  local sources
  sources="$(jq -r '
    [ (if (.host_profile // "") != "" then 1 else empty end),
      (if has("install")            then 1 else empty end) ] | length
  ' <<<"$profile")"
  if (( sources == 0 )); then
    echo "profile: no install source — set host_profile or install" >&2
    return 1
  elif (( sources > 1 )); then
    echo "profile: exactly one install source allowed" \
         "(host_profile xor install)" >&2
    return 1
  fi

  local hp
  hp="$(jq -r '.host_profile // empty' <<<"$profile")"
  if [[ -n "$hp" ]] \
     && [[ ! -f "$hosts_dir/$hp/install.template.jsonc" \
        && ! -f "$hosts_dir/vm/$hp/install.template.jsonc" ]]; then
    echo "profile: host_profile '$hp' ships no install.template.jsonc" >&2
    return 1
  fi

  # verify.mounts entries are <dataset>:/<mount>; verify.owned are /<mount>:<user>
  local bad
  bad="$(jq -r '
    (.verify.mounts // [])[] | select(test("^[^:]+:/.+") | not)' <<<"$profile")"
  [[ -z "$bad" ]] || {
    echo "profile: verify.mounts entry '$bad' must be dataset:/mount" >&2
    return 1
  }
  bad="$(jq -r '
    (.verify.owned // [])[] | select(test("^/[^:]+:[^:]+$") | not)' <<<"$profile")"
  [[ -z "$bad" ]] || {
    echo "profile: verify.owned entry '$bad' must be /mount:user" >&2
    return 1
  }
}
