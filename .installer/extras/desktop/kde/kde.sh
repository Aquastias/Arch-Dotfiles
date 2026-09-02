#!/usr/bin/env bash
# =============================================================================
# extras/desktop/kde/kde.sh — KDE Plasma Desktop
# =============================================================================
# Installs the KDE Plasma shell + applications and seeds the DE config
# defaults (Breeze Dark look, cursors, SDDM theme, first-run state — ADR 0088).
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

# Seed root for the DE config defaults the adapter writes (ADR 0088). Default
# `/` (the chroot); tests point KDE_SEED_ROOT at a temp dir. /etc/skel/.config
# holds user-owned, later-editable state copied into each home at user
# creation; /etc/xdg holds read-only system fallbacks.
SEED_ROOT="${KDE_SEED_ROOT:-/}"

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

  # ── DEFAULT LOOK: Breeze Dark, seeded so a fresh login is ready ───────────
  # (ADR 0088). Global look-and-feel + Papirus-Dark icons in /etc/skel so each
  # user owns a writable, still-changeable copy; breeze-gtk + kde-gtk-config
  # (installed above) make GTK apps follow the dark look.
  section "KDE Default Look (Breeze Dark)"

  _seed_write etc/skel/.config/kdeglobals <<'EOF'
[General]
ColorScheme=BreezeDark
widgetStyle=Breeze

[Icons]
Theme=Papirus-Dark

[KDE]
LookAndFeelPackage=org.kde.breezedark.desktop
EOF

  # Cursor: Bibata Modern Ice, the fleet default shared with niri/Hyprland (ADR
  # 0098; bibata-cursor-git in this adapter's aur). Size 24.
  _seed_write etc/skel/.config/kcminputrc <<'EOF'
[Mouse]
cursorTheme=Bibata-Modern-Ice
cursorSize=24
EOF

  # Non-KDE (GTK/X) apps read the cursor from ~/.icons/default.
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

  info "Seeded Breeze Dark look (Papirus icons, Bibata cursor, GTK, SDDM)."

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

  # Baloo file indexing ON so desktop search works from first login.
  _seed_write etc/skel/.config/baloofilerc <<'EOF'
[Basic Settings]
Indexing-Enabled=true
EOF

  # Konsole: a pre-created default profile so first launch is not the bare
  # "no profile" state.
  _seed_write etc/skel/.config/konsolerc <<'EOF'
[Desktop Entry]
DefaultProfile=Default.profile
EOF
  _seed_write etc/skel/.local/share/konsole/Default.profile <<'EOF'
[Appearance]
ColorScheme=Breeze

[General]
Name=Default
Parent=FALLBACK/
EOF

  # Dolphin: stamp the config version so migration / "what's new" popups do not
  # fire on first launch.
  _seed_write etc/skel/.config/dolphinrc <<'EOF'
[General]
Version=200
EOF

  info "Seeded first-run defaults (welcome off, Baloo on, Konsole, Dolphin)."
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
