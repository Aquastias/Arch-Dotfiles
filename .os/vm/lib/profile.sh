#!/usr/bin/env bash
# =============================================================================
# vm/lib/profile.sh — VM Profile resolution (deep, pure)
# =============================================================================
# Resolves a JSONC VM Profile (already stripped to JSON by the caller) to full
# install.jsonc text on stdout. A profile names its install config via exactly
# one source: a top-level host_profile (Install Template merge), an inline
# install object (emitted verbatim), or install:"repo" (the committed
# install.jsonc, system.hostname patched from the profile name).
# No libvirt, no TTY. Reuses lib/picker.sh + lib/jsonc.sh unchanged.
#
# Sourced by vm/vm.sh and tests/vm/profile.bats.
# =============================================================================

# shellcheck source=../../lib/picker.sh
source "${BASH_SOURCE[0]%/*}/../../lib/picker.sh"

# profile_resolve_config <profile_json> <hosts_dir> <repo_jsonc_path>
#   Emits the resolved install.jsonc on stdout. Assumes the profile already
#   passed profile_validate (exactly one install source).
profile_resolve_config() {
  local profile="$1" hosts_dir="$2" repo_jsonc="$3"
  local host_profile install_type install_str
  host_profile="$(jq -r '.host_profile // empty' <<<"$profile")"
  if [[ -n "$host_profile" ]]; then
    _profile_resolve_host "$profile" "$hosts_dir" "$host_profile"
    return
  fi
  install_type="$(jq -r '.install | type' <<<"$profile")"
  if [[ "$install_type" == "object" ]]; then
    jq '.install' <<<"$profile"
  elif [[ "$install_type" == "string" ]]; then
    install_str="$(jq -r '.install' <<<"$profile")"
    if [[ "$install_str" == "repo" ]]; then
      _profile_resolve_repo "$profile" "$repo_jsonc"
    else
      echo "profile: unknown install string '$install_str' (expected \"repo\")" >&2
      return 1
    fi
  fi
}

# profile_disk_devices <count>
#   Emits /dev/sda, /dev/sdb, … one per line, derived from the disk count.
profile_disk_devices() {
  local count="$1" i letters="abcdefghijklmnopqrstuvwxyz"
  for (( i = 0; i < count; i++ )); do
    printf '/dev/sd%s\n' "${letters:i:1}"
  done
}

# _profile_resolve_host <profile_json> <hosts_dir> <host>
#   Resolves a host_profile reference: merge the Install Template, derive the
#   OS mode (template pin, else profile layout.mode), map disk count to
#   /dev/sdX, and hand off to picker_assemble_config — the single source of
#   truth the Pre-Install Picker uses.
_profile_resolve_host() {
  local profile="$1" hosts_dir="$2" host="$3"
  local template pin mode count
  template="$(picker_load_template "$hosts_dir" "$host")" || return 1
  pin="$(picker_pin_from_template "$template")" || return 1
  if [[ -z "$pin" ]]; then
    mode="$(jq -r '.layout.mode // empty' <<<"$profile")"
    [[ -n "$mode" ]] \
      || { echo "profile: host '$host' is unpinned — layout.mode required" >&2
           return 1; }
  elif [[ "$pin" == single ]]; then
    mode=single
  else
    mode="${pin#*$'\t'}"   # multi<TAB>topology → topology
  fi
  count="$(jq -r '.hardware.disks | length' <<<"$profile")"
  local disks; mapfile -t disks < <(profile_disk_devices "$count")
  picker_assemble_config "$template" "$host" "$mode" "${disks[@]}"
}

# _profile_resolve_repo <profile_json> <repo_jsonc_path>
#   Emits the committed install.jsonc with only system.hostname patched to the
#   profile name.
_profile_resolve_repo() {
  local profile="$1" repo_jsonc="$2" name
  name="$(jq -r '.name' <<<"$profile")"
  jsonc_strip "$repo_jsonc" \
    | jq --arg h "$name" '.system = (.system // {}) | .system.hostname = $h'
}
