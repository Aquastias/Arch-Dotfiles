#!/usr/bin/env bash
# =============================================================================
# extras/dm/noctalia-greeter/noctalia-greeter.sh — noctalia-greeter Display
# Manager Adapter
# =============================================================================
# One of the Display Manager Adapters (ADR 0069), dispatched by the Environment
# Runner after the desktop loop when the resolved display_manager is
# `noctalia-greeter` (ADR 0158). The greeter runs under greetd — greetd launches
# noctalia-greeter-session, which starts the bundled wlroots compositor and the
# greeter inside it — so the greetd base (VT 2, `greeter` user) is the shared
# greetd-config.sh. Installed from the official repos only, never the AUR.
#
# Injectable seams (tests):
#   GREETD_CONF_DIR   — greetd config dir (default: /etc/greetd)
#   GREETER_STATE_DIR — the greeter's sync.toml dir
#                       (default: /var/lib/noctalia-greeter)
#   ROOT              — prefix for the config writes (default: empty)
# =============================================================================
set -Eeuo pipefail

script_path="${BASH_SOURCE[0]}"
[[ "$script_path" == */* ]] || script_path="./$script_path"
SCRIPT_DIR="$(cd "${script_path%/*}" && pwd)"
GREETD_CONF_DIR="${GREETD_CONF_DIR:-/etc/greetd}"
GREETER_STATE_DIR="${GREETER_STATE_DIR:-/var/lib/noctalia-greeter}"
ROOT="${ROOT:-}"

# shellcheck disable=SC2034  # read by extras-common.sh after sourcing
DE_TAG=noctalia-greeter
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/extras-common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/greetd-config.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/default-session.sh"

section "Display Manager: greetd + noctalia-greeter"
pacman -S --noconfirm --needed greetd noctalia-greeter

greetd_config_write /usr/bin/noctalia-greeter-session

# niri/Hyprland enable seatd (ADR 0068): libseat tries /run/seatd.sock first,
# which only the `seat` group may open, and logind's fallback cannot grant DRM
# master on some GPUs. The DE adapters ran first, so the group exists iff seatd.
if getent group seat >/dev/null; then
  usermod -aG seat greeter
  info "greeter added to the seat group (seatd)."
fi

# Default Session (ADR 0159): the greeter remembers its last session in
# sync.toml `[session].last` by desktop entry, which a fresh login preselects;
# `[session].default` would override every later pick. Seeded first: the setup
# step keeps an existing sync.toml and only fixes its owner and mode.
if _default_session="$(default_session_id)"; then
  mkdir -p "${ROOT}${GREETER_STATE_DIR}"
  printf '[session]\nlast = "%s"\n' "$_default_session" \
    > "${ROOT}${GREETER_STATE_DIR}/sync.toml"
  info "Default Session: ${_default_session}."
fi

# Create greeter.toml + sync.toml in /var/lib/noctalia-greeter, owned by the
# greeter user (the packaged tmpfiles rule only makes the directory).
GREETER_USER=greeter noctalia-greeter-apply-appearance --setup-system

systemctl enable greetd
info "greetd + noctalia-greeter enabled."
