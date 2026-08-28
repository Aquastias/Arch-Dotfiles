#!/usr/bin/env bash
# =============================================================================
# lib/packages/niri.sh — niri package sets (pure, single source of truth)
# =============================================================================
# The niri Desktop Environment Adapter's package names, shared by the install
# path (extras/desktop/niri/niri.sh, in the chroot) and the Package Resolver
# (resolver.sh, on the host), so what installs and what the query reports can
# never drift (mirrors base.sh / gpu.sh / audio.sh). Pure: name lists only —
# the DECISION to install (niri selected; niri_shell=noctalia) stays with each
# caller (ADR 0090).
# =============================================================================

[[ -n "${_NIRI_SH_SOURCED:-}" ]] && return 0
_NIRI_SH_SOURCED=1

# niri_core_packages — the minimum working-session core, one package per line
# (ADR 0021/0062/0090). niri ships its own session file + niri-session and pulls
# seatd; seatd is listed explicitly so the adapter enables it and the resolver
# reports it. The GNOME portal is for screencasting; the GTK portal is the
# fallback both are wired to by the packaged niri-portals.conf.
niri_core_packages() {
  printf '%s\n' \
    niri \
    seatd \
    xdg-desktop-portal-gnome \
    xdg-desktop-portal-gtk \
    polkit-kde-agent \
    wl-clipboard
}

# noctalia_preset_packages — the non-negotiable base of the Noctalia work preset
# (ADR 0090), one package per line: the Noctalia shell itself (v5, extra repo),
# the kitty terminal (Noctalia is not a terminal), and brightnessctl (Noctalia's
# brightness OSD shells out to it). Optional companions (cava, cliphist,
# bitwarden-cli) are toggles in install-niri.jsonc, added by their callers.
noctalia_preset_packages() {
  printf '%s\n' \
    noctalia \
    kitty \
    brightnessctl
}

# noctalia_bitwarden_packages — the backend for the Bitwarden vault plugin (ADR
# 0090). The official plugin requires the official Bitwarden CLI (`bw` on PATH);
# it does NOT work with rbw. bitwarden-cli is in the extra repo.
noctalia_bitwarden_packages() {
  printf '%s\n' bitwarden-cli
}
