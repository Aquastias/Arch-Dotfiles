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
    print-manager

  systemctl enable sddm
  info "Plasma shell installed. SDDM enabled."
fi

# =============================================================================
# KDE APPLICATIONS
# =============================================================================
if [[ "$do_apps" == "true" ]]; then
  section "KDE Applications"

  # apps_list is a 2-level Categorized List { category: { pkg: bool } }.
  # Parse in bool mode via command substitution so a shape/leaf/category
  # violation aborts the install here (error() exit propagates under set -e);
  # a process substitution would swallow it.
  apps_json="$(jsonc "$KDE_JSON" | jq -c '.apps_list')"
  apps_out="$(categorized_list_parse "$apps_json" bool apps_list)"
  kde_apps=()
  [[ -n "$apps_out" ]] && mapfile -t kde_apps <<< "$apps_out"

  if [[ ${#kde_apps[@]} -gt 0 ]]; then
    pacman -S --noconfirm --needed "${kde_apps[@]}"
    info "Installed ${#kde_apps[@]} KDE applications."
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
if [[ "$do_shell" == "true" ]]; then info "  ✔  Plasma Shell + SDDM"; fi
if [[ "$do_apps" == "true" ]]; then
  info "  ✔  KDE Applications (${#kde_apps[@]} apps)"
fi
