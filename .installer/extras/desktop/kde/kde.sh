#!/usr/bin/env bash
# =============================================================================
# extras/desktop/kde/kde.sh — KDE Plasma Desktop
# =============================================================================
# Installs the KDE Plasma shell + applications and seeds the DE config: the
# operator's captured Plasma settings (ADR 0111 — vendored under skel/, copied
# verbatim), plus the non-captured GTK-cursor/SDDM/first-run seeds (ADR 0088).
# Package selection is driven by install-kde.jsonc in the same directory.
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KDE_JSON="${KDE_JSON:-${SCRIPT_DIR}/install-kde.jsonc}"

# shellcheck disable=SC2034  # read by chroot/extras-common.sh after sourcing
DE_TAG=KDE
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/extras-common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/config/categorized-list.sh"

[[ -f "$KDE_JSON" ]] || {
  echo "[KDE] ERROR: install-kde.jsonc not found at ${KDE_JSON}"
  exit 1
}

# Honor an explicit `false` (jq's `//` treats false as empty, so `.shell //
# true` would wrongly resolve a disabled section back to true).
_KDE_BOOL='if . == false then false else true end'
do_shell="$(jsonc "$KDE_JSON" | jq -r ".shell | $_KDE_BOOL")"
do_apps="$(jsonc "$KDE_JSON" | jq -r ".apps | $_KDE_BOOL")"

# Stock (pure) KDE (ADR 0112): the plasma-meta shell only — no captured seed,
# no apps. Resolved from ENVIRONMENT_STOCK, threaded from the host (chroot.sh).
STOCK="${ENVIRONMENT_STOCK:-false}"
if [[ "$STOCK" == true ]]; then do_apps=false; fi

# Seed root for the DE config defaults the adapter writes (ADR 0088). Default
# `/` (the chroot); tests point KDE_SEED_ROOT at a temp dir. /etc/skel/.config
# holds user-owned, later-editable state copied into each home at user
# creation; /etc/xdg holds read-only system fallbacks.
SEED_ROOT="${KDE_SEED_ROOT:-/}"

# Vendored captured Plasma settings (ADR 0111) copied verbatim into skel. The
# operator's arch-combined config, snapshotted here; tests override the source.
KDE_SKEL_SRC="${KDE_SKEL_SRC:-${SCRIPT_DIR}/skel}"

# _seed_write <relative-path> — write stdin to <SEED_ROOT>/<relative-path>,
# creating parent dirs. One place owns the skel/xdg write mechanics.
_seed_write() {
  local dst="${SEED_ROOT%/}/$1"
  mkdir -p "$(dirname "$dst")"
  cat > "$dst"
}

# =============================================================================
# PLASMA SHELL
# =============================================================================
if [[ "$do_shell" == "true" ]]; then
  section "KDE Plasma Shell"
  # The shell package set is DATA — the shell_packages Categorized List in
  # install-kde.jsonc, parsed the same way apps are (bool mode). One source of
  # truth the Package Resolver reads too, so install and query cannot drift; the
  # rationale for the non-obvious members (plasma-x11-session fallback session,
  # sddm-kcm the KCM not in plasma-meta, the wayland/portal/icon pieces) is
  # documented in the jsonc. The sddm PACKAGE + enablement are the SDDM Display
  # Manager Adapter's (ADR 0069), not KDE's.
  shell_pkgs=()
  _shell_json="$(jsonc "$KDE_JSON" | jq -c '.shell_packages // {}')"
  if [[ "$_shell_json" != "{}" ]]; then
    mapfile -t shell_pkgs < <(categorized_list_parse "$_shell_json" bool \
      shell_packages)
  fi
  if [[ ${#shell_pkgs[@]} -gt 0 ]]; then
    mapfile -t shell_pkgs < <(printf '%s\n' "${shell_pkgs[@]}" | sort -u)
    pacman -S --noconfirm --needed "${shell_pkgs[@]}"
  fi

  # The display manager is no longer the KDE adapter's concern (ADR 0069): the
  # resolved Display Manager Adapter owns package + enable. KDE only ships the
  # Plasma sessions the greeter offers.
  info "Plasma shell installed."

  # Stock (pure) KDE stops at the shell (ADR 0112): no captured seed, no
  # first-run — upstream Breeze. Everything below is the opinionated look.
  if [[ "$STOCK" != true ]]; then

  # ── CAPTURED PLASMA SETTINGS, seeded so a fresh login is ready ────────────
  # (ADR 0111). Copy the operator's vendored captured config files verbatim into
  # /etc/skel, konsave-style — whole-file copy, no heredocs, so the custom
  # colour scheme (inline in kdeglobals), virtual desktops, kwin plugins/tiling,
  # widget layout, shortcuts (incl. Meta+X close — ADR 0113), lock timeout and
  # klipper all arrive together. Supersedes the ADR 0088 Breeze-Dark heredocs;
  # the non-captured first-run/GTK/SDDM seeds below are retained. The host-
  # specific monitor config (kscreenrc/kwinoutputconfig.json) is deliberately
  # NOT vendored — resolution stays autodetected (ADR 0110).
  section "KDE Captured Plasma Settings"

  if [[ -d "${KDE_SKEL_SRC}/.config" ]]; then
    _skel_dst="${SEED_ROOT%/}/etc/skel/.config"
    mkdir -p "$_skel_dst"
    _seeded=0
    for _cf in "${KDE_SKEL_SRC}/.config/"*; do
      [[ -f "$_cf" ]] && { cp "$_cf" "$_skel_dst/"; _seeded=$((_seeded + 1)); }
    done
    info "Seeded captured Plasma settings (${_seeded} files)."
  else
    warn "No captured skel at ${KDE_SKEL_SRC}/.config — seeding first-run only."
  fi

  # Avatar (ADR 0121): seed the operator's avatar as ~/.face so useradd -m copies
  # it into each home; create-user.sh points the Primary User's AccountsService
  # record at it. Not a .config file, so copied on its own (binary-safe cat).
  if [[ -f "${KDE_SKEL_SRC}/.face" ]]; then
    _seed_write etc/skel/.face < "${KDE_SKEL_SRC}/.face"
    info "Seeded avatar (~/.face)."
  fi

  # GTK/X cursor: Bibata Modern Ice via ~/.icons/default (ADR 0098). KDE apps
  # follow the captured kcminputrc; this covers non-KDE toolkits, which read
  # ~/.icons/default, not kcminputrc.
  _seed_write etc/skel/.icons/default/index.theme <<'EOF'
[Icon Theme]
Inherits=Bibata-Modern-Ice
EOF

  # SDDM login theme, in its own drop-in so it merges with the Display Manager
  # Adapter's session-dirs file rather than clobbering it (ADR 0069). Only the
  # THEME is set here — package and enablement stay dm-sddm's (ADR 0088).
  _seed_write etc/sddm.conf.d/20-kde-theme.conf <<'EOF'
[Theme]
Current=breeze
EOF

  # SDDM login background = the Horos wallpaper, so the login screen matches the
  # lock screen (captured kscreenlockerrc also points at Horos) — ADR 0121. The
  # breeze SDDM theme reads its background from theme.conf.user; an absolute path
  # to a Horos image that plasma-meta always ships (Horos ∈ oxygen → plasma-meta,
  # so it is present on every KDE install).
  _seed_write usr/share/sddm/themes/breeze/theme.conf.user <<'EOF'
[General]
background=/usr/share/wallpapers/Horos/contents/images/5120x2880.png
type=image
showClock=true
EOF

  info "Seeded captured look + GTK cursor + SDDM theme + Horos login bg."

  # ── FIRST-RUN: seed a "not first launch" state (ADR 0088, Q4-B) ───────────
  # Scope is the reliably-suppressible defaults — the Plasma Welcome Center
  # (the visible first-login wizard), Baloo, and the two apps with a stable
  # first-run key (Konsole profile, Dolphin config version). Other apps have no
  # dependable Plasma-6 first-run flag, so none is guessed.
  section "KDE First-Run Defaults"

  # Plasma Welcome Center: hide its autostart so a fresh session opens straight
  # to the desktop instead of the first-login wizard.
  _seed_write etc/skel/.config/autostart/plasma-welcome.desktop <<'EOF'
[Desktop Entry]
Hidden=true
EOF

  # Belt-and-suspenders welcome suppression (ADR 0121): plasma-welcome shows only
  # when its own LastSeenVersion is older than the installed version, so stamp
  # the INSTALLED version (pacman -Q, not a captured static one that goes stale
  # on upgrade). A no-op if the package is somehow absent.
  _pw_ver="$(pacman -Q plasma-welcome 2>/dev/null | awk '{print $2}')"
  if [[ -n "$_pw_ver" ]]; then
    _seed_write etc/skel/.config/plasma-welcomerc <<EOF
[General]
LastSeenVersion=$_pw_ver
EOF
  fi

  # Audio line in/out at 100% on first login (ADR 0121). WirePlumber restore
  # state is device-keyed, so instead of vendoring it, an idempotent autostart
  # raises the default sink AND source to full volume once the session's PipeWire
  # is up. `|| true` per node so a missing source never fails the session start.
  _seed_write etc/skel/.config/autostart/kde-audio-full-volume.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Set audio to 100% (KDE)
Comment=Raise default sink and source to full volume on first login (ADR 0121)
Exec=sh -c "wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0 || true; wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 1.0 || true"
OnlyShowIn=KDE;
NoDisplay=true
EOF

  # Combined-box KDE session reset (ADR 0116/0123): on a shared-$HOME box that
  # also runs niri/Hyprland, a Noctalia compositor session leaves the shared
  # theme/cursor state Noctalia-colored — gsettings gtk-theme at adw-gtk3-dark
  # (ADR 0116), and now that kcolorscheme is on fleet-wide (ADR 0123) the shared
  # kdeglobals colored by Noctalia too, plus a possible cursor change. Plasma does
  # NOT self-reset these on login (VM-verified). A KDE-only autostart reasserts
  # the Breeze look; the compositor side reasserts its own state via Noctalia on
  # the next niri/Hyprland login, so the sessions stay symmetric. ONLY on a
  # combined box — on pure KDE it would clobber the operator's own look. The logic
  # lives in a FIXED-path helper (/usr/local/bin), not a $HOME script the systemd
  # XDG-autostart generator would mangle, and not an inline Exec (too complex to
  # quote safely with the cursor read-back). plasma-apply-colorscheme's live
  # KGlobalSettings notify repaints already-open KColorScheme apps; the cursor is
  # read from kcminputrc so it honours the operator's KDE cursor, not a hardcode.
  _ed=" ${ENVIRONMENT_DESKTOP:-} "
  if [[ "$_ed" == *" niri "* || "$_ed" == *" hyprland "* ]]; then
    _seed_write usr/local/bin/kde-session-reset <<'EOF'
#!/bin/sh
# Combined box (ADR 0116/0123): reassert KDE's Breeze look on Plasma login after
# a niri/Hyprland session left the shared theme/cursor state Noctalia-colored.
gsettings set org.gnome.desktop.interface gtk-theme Breeze
gsettings set org.gnome.desktop.interface color-scheme prefer-dark
plasma-apply-colorscheme BreezeDark
c=$(kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme)
[ -n "$c" ] && gsettings set org.gnome.desktop.interface cursor-theme "$c"
EOF
    chmod 0755 "${SEED_ROOT%/}/usr/local/bin/kde-session-reset"
    _seed_write etc/skel/.config/autostart/kde-session-reset.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=KDE session reset (Breeze)
Comment=Reassert Breeze theme + colours + cursor on Plasma login (ADR 0116/0123)
Exec=/usr/local/bin/kde-session-reset
OnlyShowIn=KDE;
NoDisplay=true
EOF
    info "Seeded combined-box KDE session reset (ADR 0116/0123)."

    # Combined-box Qt platform-theme un-leak (ADR 0122): niri/Hyprland set
    # QT_QPA_PLATFORMTHEME=qt6ct per-compositor (ADR 0102) and the compositor
    # exports it into the shared systemd --user / D-Bus activation env, which
    # OUTLIVES the compositor session. A same-boot login to Plasma then inherits
    # it, so Qt/Kirigami KDE apps (e.g. System Settings) render Noctalia's qt6ct
    # palette instead of Breeze. A Plasma env script (sourced by startplasma
    # before plasmashell) strips it so Plasma falls back to plasma-integration
    # (Breeze). A no-op on a fresh KDE boot (var unset). ONLY on a combined box.
    _seed_write etc/skel/.config/plasma-workspace/env/kde-unset-qt-platformtheme.sh <<'EOF'
# Combined box (ADR 0122): a prior niri/Hyprland session on this boot exported
# QT_QPA_PLATFORMTHEME=qt6ct into the shared systemd --user / D-Bus activation
# env, which outlives it. Strip it so Plasma uses plasma-integration (Breeze),
# not Noctalia's qt6ct palette. Runs before plasmashell; no-op if unset.
unset QT_QPA_PLATFORMTHEME
systemctl --user unset-environment QT_QPA_PLATFORMTHEME 2>/dev/null || true
EOF
    info "Seeded combined-box Qt platform-theme un-leak (ADR 0122)."
  fi

  # Baloo file indexing ON so desktop search works from first login.
  _seed_write etc/skel/.config/baloofilerc <<'EOF'
[Basic Settings]
Indexing-Enabled=true
EOF

  # Konsole: the captured konsolerc points DefaultProfile at Default.profile, so
  # seed that profile (it is not one of the captured .config files).
  _seed_write etc/skel/.local/share/konsole/Default.profile <<'EOF'
[Appearance]
ColorScheme=Breeze

[General]
Name=Default
Parent=FALLBACK/
EOF

  # Konsole and Dolphin rc files themselves arrive via the captured seed above
  # (both carry the operator's stamped config version already).
  info "Seeded first-run defaults (welcome off, Baloo on, Konsole profile)."
  fi  # end stock guard
fi

# =============================================================================
# KDE APPLICATIONS
# =============================================================================
if [[ "$do_apps" == "true" ]]; then
  section "KDE Applications"

  # Three sibling Categorized Lists { category: { pkg: bool } } feed one
  # pacman pass: apps_list (kde-applications group members), apps_extra
  # (KDE-ecosystem repo apps outside that group — ADR 0087), and plugins
  # (per-app optdepend enhancers — ADR 0088). Parse each in bool mode via
  # command substitution so a shape/leaf/category violation aborts the install
  # here (error() exit propagates under set -e); a process substitution would
  # swallow it. An absent section contributes nothing.
  kde_apps=()
  for _sec in apps_list apps_extra plugins; do
    _sec_json="$(jsonc "$KDE_JSON" | jq -c ".${_sec} // {}")"
    [[ "$_sec_json" == "{}" ]] && continue
    _sec_out="$(categorized_list_parse "$_sec_json" bool "$_sec")"
    [[ -n "$_sec_out" ]] \
      && mapfile -t -O "${#kde_apps[@]}" kde_apps <<< "$_sec_out"
  done

  if [[ ${#kde_apps[@]} -gt 0 ]]; then
    # Sections may share a package (e.g. an imageformats plugin under two
    # apps); dedupe before the single install pass.
    mapfile -t kde_apps < <(printf '%s\n' "${kde_apps[@]}" | sort -u)
    pacman -S --noconfirm --needed "${kde_apps[@]}"
    info "Installed ${#kde_apps[@]} KDE packages."
  else
    info "No KDE applications selected (all set to false in install-kde.jsonc)."
  fi
fi

# =============================================================================
# CLEAN CACHE
# =============================================================================
section "Cleaning Package Cache"
# Try paccache first; fall back to a glob-based delete. Both branches end in
# `|| true` to make the section idempotent under `set -e`. Wrapped in an
# explicit if/else to avoid the SC2015 A && B || C antipattern.
if ! paccache -rk0 --noconfirm 2>/dev/null; then
  rm -f /var/cache/pacman/pkg/*.pkg.tar.zst \
    /var/cache/pacman/pkg/*.pkg.tar.xz 2>/dev/null || true
fi

section "KDE Installation Complete"
if [[ "$do_shell" == "true" ]]; then info "  ✔  Plasma Shell"; fi
if [[ "$do_apps" == "true" ]]; then
  info "  ✔  KDE Applications (${#kde_apps[@]} apps)"
fi
