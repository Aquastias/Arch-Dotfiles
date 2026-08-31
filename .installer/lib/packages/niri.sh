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
# brightness OSD shells out to it). Optional companions (cava, cliphist) are
# toggles in install-niri.jsonc, added by their callers.
noctalia_preset_packages() {
  printf '%s\n' \
    noctalia \
    kitty \
    brightnessctl
}

# noctalia_community_plugins — the enriched preset's community plugin set (ADR
# 0093/0094), one name per line. The name is BOTH the community-plugins subdir
# and the install-niri.jsonc bool key; canonical ids are read from each
# plugin.toml at vendor time. Shared by the adapter (installs+vendors), the
# Package Resolver (reports deps), and the stowed config.toml enabled list (a
# drift guard keeps them in step), so the set cannot drift. The laptop-gated
# battery plugins are added by their own caller (ADR 0093), not listed here.
# bitwarden and mini-docker were dropped from the default set (ADR 0094).
noctalia_community_plugins() {
  printf '%s\n' \
    keymap niri-active-workspace niri-animations niri-displays sharednd \
    screen-toolkit wl-screen-mirror arch-updater audio-switcher procmon cat \
    gamer-mode drive-health eyecare file-search shell-command ssh-launcher \
    custom-shortcut udiskie todo wallpaper-switcher portctl game-launcher \
    hotspot bookmarks llamanager dns-switcher
}

# noctalia_laptop_plugins — the laptop-gated battery plugins (ADR 0093), added
# to the enriched set only on a machine with a battery. battery-power-management
# already does charge-limit + profiles + draw, so battery-threshold is not
# shipped (it would duplicate the charge limit).
noctalia_laptop_plugins() {
  printf '%s\n' battery-power-management battery-widget
}

# noctalia_plugin_deps <name> — the official-repo Arch packages a plugin's
# wrapped system tools need (ADR 0093), one per line; empty for none. Grounded
# per each plugin.toml `dependencies`. Excludes: base-already tools (niri,
# pipewire, pacman, polkit, coreutils), alt-compositor deps (hyprland, mango —
# a pure niri host), AUR-only deps (wl-screenrec, paru/yay — an extra-repo
# recorder and the system AUR helper cover these), and heavyweight optional
# integrations (gimp, mpv, a second recorder/annotator), and hyprpicker
# (dropped with color_picker per ADR 0093 — screen-toolkit picks via slurp+grim).
# --needed dedups shared tools (upower, power-profiles-daemon, xdg-utils,
# procps-ng).
noctalia_plugin_deps() {
  case "$1" in
    keymap)           printf '%s\n' xdg-utils ;;
    screen-toolkit)
      printf '%s\n' slurp grim tesseract imagemagick zbar ffmpeg jq \
        translate-shell bc xdg-utils satty wf-recorder ;;
    wl-screen-mirror) printf '%s\n' wl-mirror ;;
    arch-updater)     printf '%s\n' pacman-contrib flatpak less xdg-utils ;;
    audio-switcher)   printf '%s\n' libpulse bluez-utils ;;
    procmon)          printf '%s\n' procps-ng ;;
    gamer-mode)       printf '%s\n' procps-ng power-profiles-daemon ;;
    drive-health)     printf '%s\n' smartmontools ;;
    eyecare)          printf '%s\n' libcanberra libpulse alsa-utils ;;
    file-search)      printf '%s\n' fzf xdg-utils ;;
    ssh-launcher)     printf '%s\n' openssh ;;
    game-launcher)    printf '%s\n' xdg-utils ;;
    hotspot)          printf '%s\n' iw ;;
    llamanager)       printf '%s\n' ollama ;;
    dns-switcher)     printf '%s\n' bind ;;
    udiskie)          printf '%s\n' udiskie udisks2 xdg-utils ;;
    battery-power-management)
      printf '%s\n' power-profiles-daemon upower ;;
    battery-widget)   printf '%s\n' upower ;;
    *) : ;; # cat, custom-shortcut, todo, wallpaper-switcher, niri-*, portctl
            # (ss⊂iproute2), bookmarks (nohup⊂coreutils) : deps in base already
  esac
}
