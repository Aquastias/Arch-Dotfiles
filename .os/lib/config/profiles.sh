#!/usr/bin/env bash
# =============================================================================
# lib/config/profiles.sh — Guided Installer Profiles picker core (ADR 0055)
# =============================================================================
# The pure core the in-menu Profiles picker stands on. Two concerns, no TTY:
#
#   - Enumerate the installable Host Profiles under a hosts/ root (names +
#     leading // header comment), so the picker can list them.
#   - Seed a Config State from a chosen profile (the profile's values merged in),
#     so picking one populates the whole menu.
#
# Distinct from lib/config/profile.sh (singular), which authors the device-less
# profile DELTA for Save. This module CONSUMES committed profiles.
#
# Public API:
#   profiles_list   <hosts-root>          → installable profile names, one per
#                                            line, alphabetical (excl core / vm)
#   profiles_header <hosts-root> <name>   → the profile's leading // header
#                                            comment (// stripped), or nothing
#   profiles_seed   <state> <profile-json>→ <state> with the profile merged over
#                                            it (profile wins), devices flattened
# =============================================================================

# shellcheck source=./skeleton.sh
[[ "$(type -t skeleton_flatten_devices)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/skeleton.sh"

# profiles_list <hosts-root> — the installable Host Profiles: immediate
# subdirectories carrying a profile.jsonc, EXCLUDING `core` (the merge base, not
# installable alone) and `vm` (harness fixtures, ADR 0035 — its profiles nest a
# level deeper and are never immediate here anyway). Alphabetical, stable.
profiles_list() {
  local root="${1:?profiles_list needs a hosts root}" d name
  for d in "$root"/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    [[ "$name" == "core" || "$name" == "vm" ]] && continue
    [[ -f "${d}profile.jsonc" ]] || continue
    printf '%s\n' "$name"
  done | LC_ALL=C sort
}

# profiles_header <hosts-root> <name> — the leading contiguous // comment block
# atop <name>'s profile.jsonc, with the `//` (and one following space) stripped,
# for the picker's preview pane. Emits nothing when the file has no leading
# comment (the caller renders the "(no description …)" fallback) or is missing.
profiles_header() {
  local root="${1:?}" name="${2:?}" f
  f="${root%/}/${name}/profile.jsonc"
  [[ -f "$f" ]] || return 0
  awk '
    /^[[:space:]]*\/\// {
      sub(/^[[:space:]]*\/\/[[:space:]]?/, "")
      print
      next
    }
    { exit }
  ' "$f"
}

# profiles_seed <state> <profile-json> — the Config State with <profile-json>
# merged OVER it (jq `*`: profile scalars/arrays replace, objects deep-merge —
# the same rule _guided_effective uses to overlay overrides on the baseline), so
# picking a profile populates every category with its values. Device paths are
# flattened out first: profiles are device-less (ADR 0036) and disks stay
# operator-picked at Proceed, so a stray devices[] never enters the seed.
profiles_seed() {
  local state="$1" profile="$2"
  profile="$(skeleton_flatten_devices "$profile")"
  jq -n --argjson s "$state" --argjson p "$profile" '$s * $p'
}
