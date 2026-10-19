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
# It scans /usr/local/share and /usr/share wayland-sessions itself (no path
# option), deduped by Name= with /usr/local first; the curated sessions win and
# the Hyprland adapter keeps the packaged uwsm session off disk (ADR 0158).
#
# Shell → greeter appearance sync stays manual (Noctalia Settings → Security →
# Noctalia Greeter, polkit-authorized); no passwordless sync is configured.
#
# Injectable seams (tests):
#   GREETD_CONF_DIR — greetd config dir (default: /etc/greetd)
#   ROOT            — prefix for the config writes (default: empty)
# =============================================================================
set -Eeuo pipefail

script_path="${BASH_SOURCE[0]}"
[[ "$script_path" == */* ]] || script_path="./$script_path"
SCRIPT_DIR="$(cd "${script_path%/*}" && pwd)"
GREETD_CONF_DIR="${GREETD_CONF_DIR:-/etc/greetd}"
ROOT="${ROOT:-}"

# shellcheck disable=SC2034  # read by extras-common.sh after sourcing
DE_TAG=noctalia-greeter
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/extras-common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/greetd-config.sh"

section "Display Manager: greetd + noctalia-greeter"
pacman -S --noconfirm --needed greetd noctalia-greeter

greetd_config_write /usr/bin/noctalia-greeter-session

# Create greeter.toml + sync.toml in /var/lib/noctalia-greeter, owned by the
# greeter user (the packaged tmpfiles rule only makes the directory).
GREETER_USER=greeter noctalia-greeter-apply-appearance --setup-system

systemctl enable greetd
info "greetd + noctalia-greeter enabled."
