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

# shellcheck source=../../lib/config/profile.sh
# Brings load_profile + assemble_profile_config (and, transitively, picker.sh +
# layers.sh) — the same loader/assembler the real install front-end uses, so a
# VM resolves the unified profile.jsonc rather than a copied Install Template.
source "${BASH_SOURCE[0]%/*}/../../lib/config/profile.sh"

# The host profile install:"repo" resolves to — the designated default. One
# knob, env-overridable, so the shipped-default smoke survives install.jsonc.
# A slim, single-disk host (arch-kde): the repo smoke forces single-disk
# layout, so the default must be a single-pinned profile (a multi host like
# desktop would demand ≥2 disks) and stay light enough for a fast smoke.
VM_DEFAULT_HOST_PROFILE="${VM_DEFAULT_HOST_PROFILE:-arch-kde}"

# profile_resolve_config <profile_json>
#   Emits the resolved install.jsonc on stdout. Assumes the profile already
#   passed profile_validate (exactly one install source). Hosts resolve through
#   the unified loader/assembler under OS_DIR.
profile_resolve_config() {
  local profile="$1"
  local host_profile install_type install_str
  host_profile="$(jq -r '.host_profile // empty' <<<"$profile")"
  if [[ -n "$host_profile" ]]; then
    _profile_resolve_host "$profile" "$host_profile"
    return
  fi
  install_type="$(jq -r '.install | type' <<<"$profile")"
  if [[ "$install_type" == "object" ]]; then
    jq '.install' <<<"$profile"
  elif [[ "$install_type" == "string" ]]; then
    install_str="$(jq -r '.install' <<<"$profile")"
    if [[ "$install_str" == "repo" ]]; then
      _profile_resolve_repo "$profile"
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

# _profile_resolve_host <profile_json> <host>
#   Resolves a host_profile reference through the unified loader/assembler:
#   load_profile reads the host's profile.jsonc (merged over core), the VM's
#   disk count maps to /dev/sdX, and assemble_profile_config assigns them onto
#   the profile's pool skeleton — the exact effective config the real
#   `install.sh --profile <host>` produces. hostname falls back to the
#   host-dir name (ADR 0036: dir ≡ hostname).
_profile_resolve_host() {
  local profile="$1" host="$2"
  local loaded pin mode count
  loaded="$(load_profile "$host")" || return $?
  # A multi host pins mode in its profile (its os_pool.topology then drives the
  # assignment). An unpinned host takes the VM's layout.mode, defaulting to
  # single; a multi topology there is rejected — pin os_pool in the profile.
  pin="$(jq -r '.mode // empty' <<<"$loaded")"
  case "$pin" in
    single | multi) mode="$pin" ;;
    *)              mode="$(jq -r '.layout.mode // "single"' <<<"$profile")" ;;
  esac

  count="$(jq -r '.hardware.disks | length' <<<"$profile")"
  local -a disks; mapfile -t disks < <(profile_disk_devices "$count")

  local assignment
  case "$mode" in
    single)
      assignment="$(jq -n --arg d "${disks[0]}" '{ mode: "single", disk: $d }')"
      ;;
    multi)
      # Slice the VM's /dev/sdX list onto every declared group by disk_count,
      # in declared order (ADR 0037) — the same producer install.sh uses, so a
      # multi-data-pool host (arch-data) assembles identically. Aborts when the
      # VM disk count != sum(disk_count).
      assignment="$(picker_build_assignment "$loaded" "${disks[@]}")" \
        || return $?
      ;;
    *)
      echo "profile: host '$host' is unpinned — pin os_pool in the profile" \
           "to use multi (layout.mode '$mode' selects no topology)" >&2
      return 1
      ;;
  esac
  assemble_profile_config "$host" "$assignment"
}

# _profile_resolve_repo <profile_json>
#   install:"repo" means "the designated default host profile" — resolve it
#   exactly as host_profile: $VM_DEFAULT_HOST_PROFILE at single (the shipped
#   default has always been single-disk).
_profile_resolve_repo() {
  local profile="$1" synth
  synth="$(jq '.layout = (.layout // {}) | .layout.mode = "single"' \
    <<<"$profile")"
  _profile_resolve_host "$synth" "$VM_DEFAULT_HOST_PROFILE"
}
