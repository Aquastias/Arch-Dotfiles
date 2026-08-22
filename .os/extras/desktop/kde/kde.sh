#!/usr/bin/env bash
# =============================================================================
# extras/desktop/kde/kde.sh — KDE Plasma Desktop
# =============================================================================
# Installs KDE Plasma shell and KDE applications ONLY.
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
do_shell="$(jsonc "$KDE_JSON" | jq -r 'if .shell == false then false else true end')"
do_apps="$(jsonc "$KDE_JSON" | jq -r 'if .apps == false then false else true end')"

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
  # plasma-x11-session is only an *optional* dep of plasma-meta, so without it
  # SDDM offers Wayland only. On GPUs where kwin_wayland can't take over the
  # display (e.g. amdgpu atomic-commit regressions), that leaves a black screen
  # at login with no fallback. Install it so an X11 session is always available.
  #
  # The trailing group is DE-tied but NOT applications, so it belongs here
  # rather than in apps_list (ADR 0021, R10/R21): sddm-kcm is a config module
  # and is not in plasma-meta; the wayland/portal/icon pieces were declared by
  # hand in the host profiles, where they installed even on a host that never
  # selected KDE. `sddm-kcm` stays here (a KDE config app); the sddm PACKAGE and
  # its enablement moved to the SDDM Display Manager Adapter (ADR 0069) so the
  # display manager is an operator choice, not KDE's to decide.
  pacman -S --noconfirm --needed \
    plasma-meta \
    plasma-workspace \
    plasma-x11-session \
    polkit-kde-agent \
    sddm-kcm \
    print-manager \
    papirus-icon-theme \
    breeze-gtk \
    kde-gtk-config \
    qt5-wayland \
    qt6-wayland \
    xdg-utils

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

  _seed_write etc/skel/.config/kcminputrc <<'EOF'
[Mouse]
cursorTheme=breeze_cursors
EOF

  # Non-KDE (GTK/X) apps read the cursor from ~/.icons/default.
  _seed_write etc/skel/.icons/default/index.theme <<'EOF'
[Icon Theme]
Inherits=breeze_cursors
EOF

  # SDDM login theme, in its own drop-in so it merges with the Display Manager
  # Adapter's session-dirs file rather than clobbering it (ADR 0069). Only the
  # THEME is set here — package and enablement stay dm-sddm's (ADR 0088).
  _seed_write etc/sddm.conf.d/20-kde-theme.conf <<'EOF'
[Theme]
Current=breeze
EOF

  info "Seeded Breeze Dark look (icons, cursors, GTK bridge, SDDM theme)."
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
    [[ -n "$_sec_out" ]] && mapfile -t -O "${#kde_apps[@]}" kde_apps <<< "$_sec_out"
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
