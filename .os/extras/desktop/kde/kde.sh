#!/usr/bin/env bash
# =============================================================================
# extras/desktop/kde/kde.sh — KDE Plasma Desktop
# =============================================================================
# Installs KDE Plasma shell and KDE applications ONLY.
# Package selection is driven by install-kde.jsonc in the same directory.
# Sourced helpers: /root/lib/common.sh provides jsonc() for JSONC parsing.
# =============================================================================

set -Eeuo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'
info() { echo -e "${GREEN}[KDE]${NC}  $*"; }
section() { echo -e "\n${CYAN}${BOLD}━━━  $*  ━━━${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KDE_JSON="${SCRIPT_DIR}/install-kde.jsonc"

# Source common.sh for jsonc() — strips // comments before piping to jq
COMMON="${SCRIPT_DIR}/../../lib/common.sh" # /root/extras/desktop/kde/../../lib/
if [[ -f "$COMMON" ]]; then
  # shellcheck source=/dev/null
  source "$COMMON"
else
  # Fallback: inline jsonc() if common.sh not available
  jsonc() { sed -e 's|[[:space:]]*//[^"]*$||' -e '/^[[:space:]]*\/\//d' "$1"; }
fi

[[ -f "$KDE_JSON" ]] || {
  echo "[KDE] ERROR: install-kde.jsonc not found at ${KDE_JSON}"
  exit 1
}

do_shell="$(jsonc "$KDE_JSON" | jq -r '.shell // true')"
do_apps="$(jsonc "$KDE_JSON" | jq -r '.apps  // true')"

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
# KDE APPLICATIONS
# =============================================================================
if [[ "$do_apps" == "true" ]]; then
  section "KDE Applications"

  mapfile -t kde_apps < <(
    jsonc "$KDE_JSON" | jq -r '.apps_list | to_entries[] | select(.value == true) | .key'
  )

  if [[ ${#kde_apps[@]} -gt 0 ]]; then
    pacman -S --noconfirm --needed "${kde_apps[@]}"
    info "Installed ${#kde_apps[@]} KDE applications."
  else
    info "No KDE applications selected (all set to false in install-kde.jsonc)."
  fi
fi

# =============================================================================
# EXTRA KDE PACKAGES
# =============================================================================
mapfile -t kde_extra < <(jsonc "$KDE_JSON" | jq -r '.extra[]? // empty')
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
  rm -f /var/cache/pacman/pkg/*.pkg.tar.zst \
    /var/cache/pacman/pkg/*.pkg.tar.xz 2>/dev/null ||
  true

section "KDE Installation Complete"
if [[ "$do_shell" == "true" ]]; then info "  ✔  Plasma Shell + SDDM"; fi
if [[ "$do_apps" == "true" ]]; then
  app_count="$(jsonc "$KDE_JSON" | jq '[.apps_list | to_entries[] | select(.value==true)] | length')"
  info "  ✔  KDE Applications (${app_count} apps)"
fi
if [[ ${#kde_extra[@]} -gt 0 ]]; then info "  ✔  Extra: ${kde_extra[*]}"; fi
