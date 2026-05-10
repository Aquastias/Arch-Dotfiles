#!/usr/bin/env bash
# extras/desktop/hyprland/hyprland.sh — Hyprland Wayland Compositor
# Injectable seams:
#   HYPR_JSON       — path to install-hyprland.jsonc (default: same directory)
#   GREETD_CONF_DIR — directory for greetd config (default: /etc/greetd)
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HYPR_JSON="${HYPR_JSON:-${SCRIPT_DIR}/install-hyprland.jsonc}"
GREETD_CONF_DIR="${GREETD_CONF_DIR:-/etc/greetd}"

DE_TAG=HYPR
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/extras-common.sh"

[[ -f "$HYPR_JSON" ]] || {
  echo "[HYPR] ERROR: install-hyprland.jsonc not found at $HYPR_JSON" >&2
  exit 1
}

# ── Core (always installed) ───────────────────────────────────────────────
section "Hyprland core"
pacman -S --noconfirm --needed hyprland xdg-desktop-portal-hyprland polkit-kde-agent

# ── Companion toggles ─────────────────────────────────────────────────────
_companion() {
  local key="$1" pkg="$2"
  local val
  val="$(jsonc "$HYPR_JSON" | jq -r ".${key}")"
  [[ "$val" != "false" ]] && pacman -S --noconfirm --needed "$pkg" || true
}

_companion bar           waybar
_companion notifications dunst
_companion launcher      fuzzel
_companion rofi          rofi-wayland
_companion terminal      alacritty
_companion lock          hyprlock
_companion idle          hypridle
_companion wallpaper     hyprpaper

# ── Display manager: greetd when KDE is absent ───────────────────────────
read -ra _desktops <<< "${ENVIRONMENT_DESKTOP:-}"
_has_kde=false
for _de in "${_desktops[@]}"; do
  [[ "$_de" == "kde" ]] && { _has_kde=true; break; }
done

if ! $_has_kde; then
  section "Display Manager: greetd"
  pacman -S --noconfirm --needed greetd greetd-tuigreet
  mkdir -p "$GREETD_CONF_DIR"
  cat > "${GREETD_CONF_DIR}/config.toml" << 'TOML'
[terminal]
vt = 1

[default_session]
command = "tuigreet --cmd Hyprland"
user = "greeter"
TOML
  systemctl enable greetd
fi

section "Hyprland installation complete"
