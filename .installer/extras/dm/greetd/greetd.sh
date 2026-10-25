#!/usr/bin/env bash
# =============================================================================
# extras/dm/greetd/greetd.sh — greetd + tuigreet Display Manager Adapter
# =============================================================================
# One of the Display Manager Adapters (ADR 0069), dispatched by the Environment
# Runner after the desktop loop when the resolved display_manager is `greetd`.
# Owns the greeter end to end: package install, config (on the shared
# greetd-config.sh base, ADR 0158), and enablement. The Desktop Environment
# Adapters no longer touch any DM — the Hyprland adapter writes the curated
# wayland-sessions, this adapter only points the greeter at them.
#
# Injectable seams (tests):
#   GREETD_CONF_DIR      — greetd config dir (default: /etc/greetd)
#   WAYLAND_SESSIONS_DIR — curated session dir the Hyprland adapter populates
#                          (default: /usr/local/share/wayland-sessions)
#   TUIGREET_CACHE_DIR   — tuigreet's remember cache
#                          (default: /var/cache/tuigreet)
#   ROOT                 — prefix for the config writes (default: empty)
# =============================================================================
set -Eeuo pipefail

script_path="${BASH_SOURCE[0]}"
[[ "$script_path" == */* ]] || script_path="./$script_path"
SCRIPT_DIR="$(cd "${script_path%/*}" && pwd)"
GREETD_CONF_DIR="${GREETD_CONF_DIR:-/etc/greetd}"
_WS_DIR_DEFAULT=/usr/local/share/wayland-sessions
WAYLAND_SESSIONS_DIR="${WAYLAND_SESSIONS_DIR:-$_WS_DIR_DEFAULT}"
TUIGREET_CACHE_DIR="${TUIGREET_CACHE_DIR:-/var/cache/tuigreet}"
ROOT="${ROOT:-}"

# shellcheck disable=SC2034  # read by extras-common.sh after sourcing
DE_TAG=greetd
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/extras-common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/greetd-config.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/default-session.sh"

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

greetd_config_write \
  "tuigreet --remember --remember-session --sessions ${_sessions_dir}"

# Default Session (ADR 0159): --remember-session preselects the session whose
# path in the --sessions dir it last recorded. The cache dir is the greeter's
# (tmpfiles), so the seed must be too, or tuigreet can never update it.
if _default_session="$(default_session_id)"; then
  mkdir -p "${ROOT}${TUIGREET_CACHE_DIR}"
  printf '%s' "${_sessions_dir}/${_default_session}.desktop" \
    > "${ROOT}${TUIGREET_CACHE_DIR}/lastsession-path"
  chown -R greeter:greeter "${ROOT}${TUIGREET_CACHE_DIR}"
  info "Default Session: ${_default_session}."
fi

systemctl enable greetd
info "greetd + tuigreet enabled (sessions: ${_sessions_dir})."
