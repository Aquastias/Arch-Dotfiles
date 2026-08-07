#!/usr/bin/env bash
# =============================================================================
# extras/dm/greetd/greetd.sh — greetd + tuigreet Display Manager Adapter
# =============================================================================
# One of the two Display Manager Adapters (ADR 0069), dispatched by the
# Environment Runner after the desktop loop when the resolved display_manager
# is `greetd`. Owns the greeter end to end: package install, config, and
# enablement. The Desktop Environment Adapters no longer touch any DM — the
# Hyprland adapter writes the curated wayland-sessions, this adapter only points
# the greeter at them.
#
# Injectable seams (tests):
#   GREETD_CONF_DIR      — greetd config dir (default: /etc/greetd)
#   WAYLAND_SESSIONS_DIR — curated session dir the Hyprland adapter populates
#                          (default: /usr/local/share/wayland-sessions)
#   ROOT                 — prefix for the config writes (default: empty)
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREETD_CONF_DIR="${GREETD_CONF_DIR:-/etc/greetd}"
_WS_DIR_DEFAULT=/usr/local/share/wayland-sessions
WAYLAND_SESSIONS_DIR="${WAYLAND_SESSIONS_DIR:-$_WS_DIR_DEFAULT}"
ROOT="${ROOT:-}"

# shellcheck disable=SC2034  # read by extras-common.sh after sourcing
DE_TAG=greetd
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/extras-common.sh"

section "Display Manager: greetd + tuigreet"
pacman -S --noconfirm --needed greetd greetd-tuigreet

# Point tuigreet at the curated /usr/local dir when it exists (the Hyprland
# adapter populated it, hiding the packaged crashy /usr/share duplicates). On a
# KDE-only greetd install Hyprland never ran, so the curated dir is absent and
# there are no duplicates to hide — fall back to the packaged /usr/share dir so
# the Plasma session still appears.
_sessions_dir="$WAYLAND_SESSIONS_DIR"
[[ -d "${ROOT}${WAYLAND_SESSIONS_DIR}" ]] \
  || _sessions_dir="/usr/share/wayland-sessions"

mkdir -p "${ROOT}${GREETD_CONF_DIR}"
cat > "${ROOT}${GREETD_CONF_DIR}/config.toml" <<TOML
[terminal]
vt = 1

[default_session]
command = "tuigreet --remember --remember-session --sessions ${_sessions_dir}"
user = "greeter"
TOML

systemctl enable greetd
info "greetd + tuigreet enabled (sessions: ${_sessions_dir})."
