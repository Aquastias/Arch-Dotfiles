#!/usr/bin/env bash
# =============================================================================
# lib/packages/niri.sh — niri core package set (pure, single source of truth)
# =============================================================================
# The niri Desktop Environment Adapter's package names, shared by the install
# path (extras/desktop/niri/niri.sh, in the chroot) and the Package Resolver
# (package-resolver.sh, on the host), so what installs and what the query
# reports can never drift (mirrors base.sh / gpu.sh / audio.sh). Pure: name
# lists only — the DECISION to install (niri selected; wayland_shell=noctalia)
# stays with each caller (ADR 0090). The Noctalia preset + plugin sets live in
# noctalia.sh.
#
# Used by: extras/desktop/niri/niri.sh, lib/packages/package-resolver.sh.
# =============================================================================

[[ -n "${_NIRI_SH_SOURCED:-}" ]] && return 0
_NIRI_SH_SOURCED=1

# niri_core_packages — the minimum working-session core, one package per line
# (ADR 0021/0062/0090). niri ships its own session file + niri-session and pulls
# seatd; seatd is listed explicitly so the adapter enables it and the resolver
# reports it. The GNOME portal is for screencasting; the GTK portal is the
# fallback both are wired to by the packaged niri-portals.conf. niri has no
# Xwayland of its own: xwayland-satellite runs X11 apps, no config needed
# (Arch Wiki: Niri#XWayland).
niri_core_packages() {
  printf '%s\n' \
    niri \
    seatd \
    xdg-desktop-portal-gnome \
    xdg-desktop-portal-gtk \
    wl-clipboard \
    xwayland-satellite
}
