#!/usr/bin/env bash
# =============================================================================
# lib/aur-helper.sh — AUR Helper resolution (ADR 0052)
# =============================================================================
# The single definition of the "paru preferred, yay fallback" rule. Sourced by
# lib/profiles/runner.sh (installer) and tools/install-pkglist.sh (booted), so
# helper resolution has one home. Pure: defines a function, no side effects.
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
