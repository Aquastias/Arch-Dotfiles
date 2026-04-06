#!/usr/bin/env bash
# =============================================================================
# extras/kde.sh — KDE Plasma Desktop
# =============================================================================
# Installs KDE Plasma shell and KDE applications ONLY.
# Package selection is driven by install-kde.json in the same directory.
# Everything else (audio, wayland, fonts, gaming, etc.) belongs in
# install.json packages.groups and is installed by pacstrap.
# =============================================================================

set -Eeuo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'
info() { echo -e "${GREEN}[KDE]${NC}  $*"; }
section() { echo -e "\n${CYAN}${BOLD}━━━  $*  ━━━${NC}"; }

# ── Locate install-kde.json ───────────────────────────────────────────────────
# When running inside chroot it is copied to /root/extras/install-kde.json
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KDE_JSON="${SCRIPT_DIR}/install-kde.json"
[[ -f "$KDE_JSON" ]] || {
  echo "[KDE] ERROR: install-kde.json not found at ${KDE_JSON}"
  exit 1
}

_jq() { jq -r "$1" "$KDE_JSON"; }

do_shell="$(_jq '.shell // true')"
do_apps="$(_jq '.apps  // true')"

# =============================================================================
# PLASMA SHELL
# =============================================================================
if [[ "$do_shell" == "true" ]]; then
  section "KDE Plasma Shell"
  pacman -S --noconfirm --needed \
    plasma-meta \
    plasma-workspace \
    polkit-kde-agent \
    sddm \
    sddm-kcm \
    extra-cmake-modules \
    kimageformats5 \
    xdg-desktop-portal-kde \
    print-manager \
    cups

  systemctl enable sddm
  systemctl enable cups
  info "Plasma shell installed. SDDM enabled."
fi

# =============================================================================
# KDE APPLICATIONS — built individually from apps_list
# =============================================================================
if [[ "$do_apps" == "true" ]]; then
  section "KDE Applications"

  # Build install list from apps_list — only entries set to true
  mapfile -t kde_apps < <(
    jq -r '.apps_list | to_entries[] | select(.value == true) | .key' "$KDE_JSON"
  )

  if [[ ${#kde_apps[@]} -gt 0 ]]; then
    pacman -S --noconfirm --needed "${kde_apps[@]}"
    info "Installed ${#kde_apps[@]} KDE applications."
  else
    info "No KDE applications selected (all set to false in install-kde.json)."
  fi
fi

# =============================================================================
# EXTRA KDE PACKAGES — install-kde.json extra[]
# =============================================================================
mapfile -t kde_extra < <(jq -r '.extra[]? // empty' "$KDE_JSON")
if [[ ${#kde_extra[@]} -gt 0 ]]; then
  section "Extra KDE Packages"
  pacman -S --noconfirm --needed "${kde_extra[@]}"
  info "Extra packages installed: ${kde_extra[*]}"
fi

# =============================================================================
# CLEAN CACHE
# =============================================================================
section "Cleaning Package Cache"
paccache -rk0 --noconfirm 2>/dev/null ||
  rm -rf /var/cache/pacman/pkg/*.pkg.tar.* 2>/dev/null ||
  true

section "KDE Installation Complete"
[[ "$do_shell" == "true" ]] && info "  ✔  Plasma Shell + SDDM"
[[ "$do_apps" == "true" ]] && info "  ✔  KDE Applications ($(
  jq '[.apps_list | to_entries[] | select(.value==true)] | length' "$KDE_JSON"
) apps)"
[[ ${#kde_extra[@]} -gt 0 ]] && info "  ✔  Extra: ${kde_extra[*]}"
