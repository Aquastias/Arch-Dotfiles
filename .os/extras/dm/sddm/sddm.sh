#!/usr/bin/env bash
# =============================================================================
# extras/dm/sddm/sddm.sh — SDDM Display Manager Adapter
# =============================================================================
# One of the two Display Manager Adapters (ADR 0069), dispatched by the
# Environment Runner after the desktop loop when the resolved display_manager
# is `sddm`. Owns SDDM end to end: package install, config, and enablement — so
# SDDM on a Hyprland-only host (where the KDE adapter never runs) still has an
# owner. Now that seatd grants aquamarine DRM master independent of the greeter
# (ADR 0068), SDDM can launch Hyprland too.
#
# Injectable seams (tests):
#   SDDM_CONF_DIR        — sddm.conf.d drop-in dir (default: /etc/sddm.conf.d)
#   WAYLAND_SESSIONS_DIR — curated session dir the Hyprland adapter populates
#                          (default: /usr/local/share/wayland-sessions)
#   ROOT                 — prefix for the config writes (default: empty)
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDDM_CONF_DIR="${SDDM_CONF_DIR:-/etc/sddm.conf.d}"
_WS_DIR_DEFAULT=/usr/local/share/wayland-sessions
WAYLAND_SESSIONS_DIR="${WAYLAND_SESSIONS_DIR:-$_WS_DIR_DEFAULT}"
ROOT="${ROOT:-}"

# shellcheck disable=SC2034  # read by extras-common.sh after sourcing
DE_TAG=sddm
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/extras-common.sh"

section "Display Manager: SDDM"
pacman -S --noconfirm --needed sddm

# Pin the curated /usr/local dir AHEAD of /usr/share for both Wayland and X11,
# so SDDM shows the same deduped session list greetd's `--sessions` gives: the
# curated hyprland.desktop shadows the packaged crashy one by basename, and
# /usr/share still supplies Plasma. This matches SDDM's own default order but
# nails it down so a packaging change can't reorder it.
mkdir -p "${ROOT}${SDDM_CONF_DIR}"
cat > "${ROOT}${SDDM_CONF_DIR}/10-session-dirs.conf" <<CONF
[Wayland]
SessionDir=${WAYLAND_SESSIONS_DIR},/usr/share/wayland-sessions

[X11]
SessionDir=/usr/local/share/xsessions,/usr/share/xsessions
CONF

systemctl enable sddm
info "SDDM enabled (curated sessions pinned ahead of /usr/share)."
