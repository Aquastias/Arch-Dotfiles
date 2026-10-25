#!/usr/bin/env bash
# =============================================================================
# lib/packages/umbriel.sh — Umbriel repo core package set (pure, single source)
# =============================================================================
# The Umbriel Desktop Environment Adapter's repo package names, shared by the
# install path (extras/desktop/umbriel/umbriel.sh, in the chroot) and the
# Package Resolver (on the host), so install and query can never drift
# (mirrors niri.sh). The compositor itself is AUR-only (ADR 0159), declared in
# the adapter's install-umbriel.jsonc `aur` list.
#
# Used by: extras/desktop/umbriel/umbriel.sh, lib/packages/package-resolver.sh.
# =============================================================================

[[ -n "${_UMBRIEL_SH_SOURCED:-}" ]] && return 0
_UMBRIEL_SH_SOURCED=1

# umbriel_core_packages — the repo half of a working session, one per line.
# seatd for DRM master (ADR 0068); the GTK portal is the fallback the packaged
# umbriel-portals.conf names after Umbriel's own (`default=umbriel;gtk`);
# wl-clipboard for the clipboard keep-alive (ADR 0147). Xwayland comes with
# the compositor package (upstream PACKAGING.md).
umbriel_core_packages() {
  printf '%s\n' \
    seatd \
    xdg-desktop-portal-gtk \
    wl-clipboard
}
