#!/usr/bin/env bash
# extras/desktop/hyprland/hyprland.sh — Hyprland Wayland Compositor
# Injectable seams:
#   HYPR_JSON       — path to install-hyprland.jsonc (default: same directory)
#   GREETD_CONF_DIR — directory for greetd config (default: /etc/greetd)
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HYPR_JSON="${HYPR_JSON:-${SCRIPT_DIR}/install-hyprland.jsonc}"
GREETD_CONF_DIR="${GREETD_CONF_DIR:-/etc/greetd}"
WAYLAND_SESSIONS_DIR="${WAYLAND_SESSIONS_DIR:-/usr/local/share/wayland-sessions}"

# shellcheck disable=SC2034  # read by chroot/extras-common.sh after sourcing
DE_TAG=HYPR
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/extras-common.sh"

[[ -f "$HYPR_JSON" ]] || {
  echo "[HYPR] ERROR: install-hyprland.jsonc not found at $HYPR_JSON" >&2
  exit 1
}

# ── Core (always installed) ───────────────────────────────────────────────
# Every package derivable from environment.desktop=hyprland (ADR 0021): the
# compositor, both portals, the polkit agent, the Wayland clipboard bridge.
section "Hyprland core"
pacman -S --noconfirm --needed \
  hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  polkit-kde-agent wl-clipboard

# ── Session launcher: direct Hyprland, not start-hyprland ─────────────────
# hyprland's packaged session (/usr/share/wayland-sessions/hyprland.desktop)
# execs /usr/bin/start-hyprland, a supervisor that aborts a few seconds into
# startup with `std::system_error: Resource deadlock avoided` (core dump) — so
# a display manager bounces straight back to the greeter while a bare `Hyprland`
# runs fine. This only bites the SDDM path (KDE co-installed): the greetd path
# below already launches `Hyprland` directly (tuigreet --cmd Hyprland). Ship a
# /usr/local session override so SDDM launches it the same way. /usr/local wins
# over /usr/share in a DM's session scan and survives hyprland upgrades.
section "Hyprland session launcher (direct)"
install -d "$WAYLAND_SESSIONS_DIR"
cat > "${WAYLAND_SESSIONS_DIR}/hyprland.desktop" << 'DESKTOP'
[Desktop Entry]
Name=Hyprland
Comment=Hyprland compositor (direct launch; avoids start-hyprland crash)
Exec=Hyprland
Type=Application
DesktopNames=Hyprland
Keywords=tiling;wayland;compositor;
DESKTOP

# ── Companion toggles ─────────────────────────────────────────────────────
# A toggle installs its package(s) unless its key is explicitly false. Keys
# may contain hyphens, so look them up via $k rather than ".key" (jq reads
# ".gtk-look" as subtraction). Trailing args are the package(s) to install.
_companion() {
  local key="$1"; shift
  local val
  val="$(jsonc "$HYPR_JSON" | jq -r --arg k "$key" '.[$k]')"
  [[ "$val" != "false" ]] && pacman -S --noconfirm --needed "$@" || true
}

_companion bar           waybar
_companion notifications dunst
_companion launcher      fuzzel
_companion rofi          rofi-wayland
_companion terminal      alacritty
_companion lock          hyprlock
_companion idle          hypridle
_companion wallpaper     hyprpaper
_companion screenshot    grim slurp
_companion gtk-look      nwg-look
_companion wofi          wofi

# ── Display manager: greetd (always, whenever Hyprland is installed) ──────
# greetd launches the compositor from a clean logind session on its own VT, so
# it acquires DRM master and the greeter→session handoff succeeds. SDDM does NOT
# on this hybrid-GPU class: even with a direct `Exec=Hyprland` it wins the
# session but the handoff leaves it without DRM master and every atomic commit
# returns EACCES (`Permission denied`) → black panel. So greetd owns the DM role
# whenever Hyprland is present — including alongside KDE, where kde.sh skips
# `systemctl enable sddm`. tuigreet's session picker still offers Plasma.
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

section "Hyprland installation complete"
