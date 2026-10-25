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
#   XORG_CONF_DIR        — xorg.conf.d dir for the VM cursor drop-in
#                          (default: /etc/X11/xorg.conf.d)
#   SDDM_STATE_DIR       — the sddm user's home, holding state.conf
#                          (default: /var/lib/sddm)
#   ROOT                 — prefix for the config writes (default: empty)
# =============================================================================
set -Eeuo pipefail

script_path="${BASH_SOURCE[0]}"
[[ "$script_path" == */* ]] || script_path="./$script_path"
SCRIPT_DIR="$(cd "${script_path%/*}" && pwd)"
SDDM_CONF_DIR="${SDDM_CONF_DIR:-/etc/sddm.conf.d}"
XORG_CONF_DIR="${XORG_CONF_DIR:-/etc/X11/xorg.conf.d}"
SDDM_STATE_DIR="${SDDM_STATE_DIR:-/var/lib/sddm}"
_WS_DIR_DEFAULT=/usr/local/share/wayland-sessions
WAYLAND_SESSIONS_DIR="${WAYLAND_SESSIONS_DIR:-$_WS_DIR_DEFAULT}"
ROOT="${ROOT:-}"

# shellcheck disable=SC2034  # read by extras-common.sh after sourcing
DE_TAG=sddm
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/extras-common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/default-session.sh"

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

# VM-only: force Xorg software cursors so SDDM's Xorg greeter never programs the
# virtio-gpu hardware cursor plane (ADR 0106). In a SPICE guest that plane is
# drawn client-side as a stale "X" overlay that lingers into the (Wayland)
# session and survives logout — the Xorg counterpart to the compositor cursor
# overrides (niri disable-cursor-plane / Hyprland no_hardware_cursors). greetd
# hosts never start Xorg, so only the SDDM path needs it. Machine-TYPE gated, so
# real hardware keeps its hardware cursor; must be present from boot (a mid-
# session apply can't retract SPICE's already-drawn overlay).
if systemd-detect-virt --vm --quiet 2>/dev/null; then
  install -d "${ROOT}${XORG_CONF_DIR}"
  cat > "${ROOT}${XORG_CONF_DIR}/10-vm-sw-cursor.conf" <<'CONF'
Section "Device"
    Identifier "Virtio SW cursor"
    Driver "modesetting"
    Option "SWcursor" "true"
EndSection
CONF
  info "VM detected — forced Xorg software cursor (SDDM greeter ghost-X fix)."
fi

# Default Session (ADR 0159): SDDM preselects the session whose absolute path
# state.conf `[Last] Session=` records, scanning SessionDir in the order pinned
# above. Written as the daemon writes it after a login, so the next pick wins.
if _default_session="$(default_session_path "$WAYLAND_SESSIONS_DIR" \
    /usr/share/wayland-sessions)"; then
  default_session_write "${SDDM_STATE_DIR}/state.conf" \
    $'[Last]\n'"Session=${_default_session}"$'\n'
fi

systemctl enable sddm
info "SDDM enabled (curated sessions pinned ahead of /usr/share)."
