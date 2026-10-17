#!/usr/bin/env bash
# =============================================================================
# lib/config/profiles.sh — Guided Installer Profiles picker core (ADR 0055)
# =============================================================================
# The pure core the in-menu Profiles picker stands on. Two concerns, no TTY:
#
#   - Enumerate the installable Host Profiles under a hosts/ root (names +
#     leading // header comment), so the picker can list them.
#   - Build the Guided baseline a chosen profile installs, so picking one
#     populates the whole menu and installs exactly that profile.
#
# Distinct from lib/config/profile-loader.sh (singular), which authors the
# device-less profile DELTA for Save. This module CONSUMES committed profiles.
#
# Public API:
#   profiles_list   <hosts-root>          → installable profile names, one per
#                                            line, alphabetical (excl core / vm)
#   profiles_header <hosts-root> <name>   → the profile's leading // header
#                                            comment (// stripped), or nothing
#   profiles_baseline <name>              → the Guided baseline for Host Profile
#                                            <name>, resolved as --profile does
#
# Used by: lib/guided/controller.sh.
# =============================================================================

# shellcheck source=./profile-loader.sh
declare -F profile_loader_load >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/profile-loader.sh"
# shellcheck source=./config-state.sh
declare -F config_state_install_defaults >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config-state.sh"
# shellcheck source=./skeleton.sh
declare -F skeleton_flatten_devices >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/skeleton.sh"

# profiles_list <hosts-root> — the installable Host Profiles: immediate
# subdirectories carrying a profile.jsonc, EXCLUDING `core` (the merge base, not
# installable alone) and `vm` (harness fixtures, ADR 0035 — its profiles nest a
# level deeper and are never immediate here anyway). Alphabetical, stable.
profiles_list() {
  local root="${1:?profiles_list needs a hosts root}" host_directory name
  for host_directory in "$root"/*/; do
    [[ -d "$host_directory" ]] || continue
    name="${host_directory%/}"
    name="${name##*/}"
    [[ "$name" == "core" || "$name" == "vm" ]] && continue
    [[ -f "${host_directory}profile.jsonc" ]] || continue
    printf '%s\n' "$name"
  done | LC_ALL=C sort
}

# profiles_header <hosts-root> <name> — the leading contiguous // comment block
# atop <name>'s profile.jsonc, with the `//` (and one following space) stripped,
# for the picker's preview pane. Emits nothing when the file has no leading
# comment (the caller renders the "(no description …)" fallback) or is missing.
profiles_header() {
  local root="${1:?}" name="${2:?}" profile_file
  profile_file="${root%/}/${name}/profile.jsonc"
  [[ -f "$profile_file" ]] || return 0
  awk '
    /^[[:space:]]*\/\// {
      sub(/^[[:space:]]*\/\/[[:space:]]?/, "")
      print
      next
    }
    { exit }
  ' "$profile_file"
}

# profiles_baseline <name> — the Guided baseline after picking Host Profile
# <name> (ADR 0157): the profile resolved exactly as `install.sh --profile`
# resolves it (the Profile Loader, then the hostname fallback), laid over the
# schema Install Defaults the menu shows. Nothing else survives — no launch
# preset, no Host Core content the profile opted out of, no earlier pick — so
# one profile produces one install through every front-end. Device paths are
# flattened out: disks stay operator-picked at Proceed. rc 1 when <name> does
# not load.
profiles_baseline() {
  local name="$1" profile
  profile="$(profile_loader_load "$name" 2>/dev/null)" || return 1
  profile="$(profile_loader_default_hostname "$name" "$profile")"
  profile="$(skeleton_flatten_devices "$profile")"
  jq -n --argjson defaults "$(config_state_install_defaults '{}')" \
    --argjson profile "$profile" '$defaults * $profile'
}
