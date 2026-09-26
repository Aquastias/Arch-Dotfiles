#!/usr/bin/env bash
# =============================================================================
# lib/aur-helper.sh — AUR Helper resolution + vetting policy (ADR 0052, 0143)
# =============================================================================
# The single definition of the "paru preferred, yay fallback" rule and of
# which helper may build from the AUR. Sourced by lib/profiles/runner.sh
# (installer) and tools/install-pkglist.sh (booted), so both rules have one
# home. Pure and SELF-CONTAINED: the booted tool sources this without
# common.sh, so it must not lean on common's helpers — uses `command -v`
# directly, not command_exists (ADR 0052).
# =============================================================================

# Resolve the AUR Helper on the current PATH: print `paru`/`yay` (paru
# preferred), returning 0 when one exists; non-zero with no output when neither
# does. The in-chroot, per-user counterpart is _profiles_detect_user_helper.
_profiles_detect_helper() {
  local h
  for h in paru yay; do
    if command -v "$h" >/dev/null 2>&1; then
      printf '%s\n' "$h"
      return 0
    fi
  done
  return 1
}

# The AUR Vetting policy (ADR 0143), one definition for the Runner and
# tools/install-pkglist.sh. Only paru builds from the AUR: its
# PreBuildCommand runs the vetter, and yay has no such hook.
_aur_helper_vets_aur() { [[ "$1" == paru ]]; }

# Print the command for a repo-only install with <helper>: under yay that is
# `yay --repo`, so nothing is built unvetted from the AUR.
_aur_helper_repo_cmd() {
  if _aur_helper_vets_aur "$1"; then printf '%s\n' "$1"
  else printf '%s --repo\n' "$1"; fi
}
