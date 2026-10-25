#!/usr/bin/env bash
# =============================================================================
# extras/desktop/umbriel/umbriel.sh — Umbriel wlroots Wayland compositor
# =============================================================================
# Core-only Desktop Environment Adapter (ADR 0021/0159), like niri. Umbriel is
# the Noctalia project's own compositor and AUR-only: the compositor and its
# portal are this adapter's install-umbriel.jsonc `aur` list, installed by the
# Profiles Runner's paru pass AFTER this script. So this adapter installs only
# the repo core and curates a session entry that resolves once the package
# ships /usr/share/wayland-sessions/umbriel.desktop (+ start-umbriel). The
# display manager is a separate Display Manager Adapter (ADR 0069).
#
# Injectable seams (tests):
#   WAYLAND_SESSIONS_DIR — curated session dir
#                          (default: /usr/local/share/wayland-sessions)
#   ROOT                 — prefix for the curated-session write (default: empty)
# =============================================================================
set -Eeuo pipefail

script_path="${BASH_SOURCE[0]}"
[[ "$script_path" == */* ]] || script_path="./$script_path"
SCRIPT_DIR="$(cd "${script_path%/*}" && pwd)"
_WS_DIR_DEFAULT=/usr/local/share/wayland-sessions
WAYLAND_SESSIONS_DIR="${WAYLAND_SESSIONS_DIR:-$_WS_DIR_DEFAULT}"
ROOT="${ROOT:-}"

# shellcheck disable=SC2034  # read by chroot/extras-common.sh after sourcing
DE_TAG=umbriel
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/extras-common.sh"
# The pure Umbriel package map, shared with the Package Resolver so install and
# query cannot drift.
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/packages/umbriel.sh"

# =============================================================================
# CORE
# =============================================================================
section "Umbriel core"
# shellcheck disable=SC2046  # word-split the one-per-line pure map into args
pacman -S --noconfirm --needed $(umbriel_core_packages)

# SEAT MANAGER — seatd (ADR 0068). Umbriel is wlroots, whose libseat tries
# seatd first; logind's fallback cannot grant DRM master on the AMD laptop. An
# Umbriel-only host must not rely on the Hyprland adapter for it. Users get the
# `seat` group from User Core.
systemctl enable seatd

# =============================================================================
# CURATED SESSION — offered to whichever Display Manager is selected (ADR 0069)
# =============================================================================
# As niri does: a greeter pointed only at the curated /usr/local dir (tuigreet)
# would miss the packaged session. The link dangles until the paru pass lands
# the package, which is still before first boot.
section "Umbriel curated session"
install -d "${ROOT}${WAYLAND_SESSIONS_DIR}"
ln -sf /usr/share/wayland-sessions/umbriel.desktop \
  "${ROOT}${WAYLAND_SESSIONS_DIR}/umbriel.desktop"
# On a KDE co-install, curate Plasma too: tuigreet reads this dir alone.
if [[ " ${ENVIRONMENT_DESKTOP:-} " == *" kde "* ]]; then
  ln -sf /usr/share/wayland-sessions/plasma.desktop \
    "${ROOT}${WAYLAND_SESSIONS_DIR}/plasma.desktop"
fi

section "Umbriel installation complete"
