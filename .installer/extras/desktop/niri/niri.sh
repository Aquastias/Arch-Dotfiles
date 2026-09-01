#!/usr/bin/env bash
# =============================================================================
# extras/desktop/niri/niri.sh — niri scrollable-tiling Wayland compositor
# =============================================================================
# Core-only Desktop Environment Adapter (ADR 0021/0062/0090): installs the
# compositor and session plumbing only. niri ships its own
# /usr/share/wayland-sessions/niri.desktop + niri-session and pulls seatd, so —
# unlike the Hyprland adapter — there is no session-launcher shim and no
# aquamarine DRM pin. The display manager is a separate, operator-selected
# Display Manager Adapter (ADR 0069) — not this adapter's concern.
#
# The optional Noctalia work shell (ADR 0090/0097) layers on top, gated on
# ENVIRONMENT_WAYLAND_SHELL; bare niri (none / unset) installs the core only.
# The preset itself is the SHARED module lib/chroot/noctalia-preset.sh (the same
# one the Hyprland adapter uses); this adapter only maps its seams and picks the
# niri config file + the niri plugin slice.
#
# Injectable seams (tests):
#   NIRI_SEED_ROOT       — prefix for /etc/skel seeds (default: / — the chroot)
#   NIRI_BAT_GLOB        — battery-presence glob for laptop detection
#                          (default: /sys/class/power_supply/BAT*)
#   NIRI_JSON            — install-noctalia.jsonc override (preset component bools)
#   NIRI_CURATED_DIR     — staged curated dotfiles source
#   WAYLAND_SESSIONS_DIR — curated session dir
#                          (default: /usr/local/share/wayland-sessions)
#   ROOT                 — prefix for the curated-session write (default: empty)
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The Noctalia preset toggles are SHARED with the Hyprland adapter (ADR 0097),
# so the file lives one level up (extras/desktop/), not under this DE.
NIRI_JSON="${NIRI_JSON:-${SCRIPT_DIR}/../install-noctalia.jsonc}"
_WS_DIR_DEFAULT=/usr/local/share/wayland-sessions
WAYLAND_SESSIONS_DIR="${WAYLAND_SESSIONS_DIR:-$_WS_DIR_DEFAULT}"
ROOT="${ROOT:-}"
# Seed root for the /etc/skel config glue (ADR 0088/0090). Default `/` (the
# chroot); tests point NIRI_SEED_ROOT at a temp dir.
SEED_ROOT="${NIRI_SEED_ROOT:-/}"

# Curated-config source (ADR 0095). chroot.sh stages the repo's single-source
# `.config`/`.local` curated niri+Noctalia dotfiles here so this adapter seeds
# them into /etc/skel — served by default, while the repo copy stays
# independently stowable. Injectable for tests.
NIRI_CURATED_DIR="${NIRI_CURATED_DIR:-${SCRIPT_DIR}/curated}"

# shellcheck disable=SC2034  # read by chroot/extras-common.sh after sourcing
DE_TAG=niri
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/extras-common.sh"
# The pure niri package map, shared with the Package Resolver so install and
# query cannot drift (ADR 0090).
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/packages/niri.sh"
# The shared Noctalia work-shell preset (ADR 0097) — install + seed logic used by
# both the niri and Hyprland adapters.
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/noctalia-preset.sh"

# =============================================================================
# CORE
# =============================================================================
section "niri core"
# shellcheck disable=SC2046  # word-split the one-per-line pure map into args
pacman -S --noconfirm --needed $(niri_core_packages)

# SEAT MANAGER — seatd (ADR 0068). niri uses libseat and takes DRM master via
# seatd directly; enable it so both greeter-launched and manual sessions acquire
# master. Users get the `seat` group from User Core (filtered out on hosts
# without seatd).
systemctl enable seatd

# =============================================================================
# CURATED SESSION — offered to whichever Display Manager is selected (ADR 0069)
# =============================================================================
# niri ships its own /usr/share/wayland-sessions/niri.desktop, but a greeter
# pointed ONLY at the curated /usr/local dir would miss it — e.g. greetd on a
# niri+Hyprland co-install, where the Hyprland adapter creates that dir and
# tuigreet reads only it. Symlink the packaged session into the curated dir so
# niri appears under any DM regardless of DE order (mirrors how the Hyprland
# adapter curates Plasma). niri-only still works via the greeter's /usr/share
# fallback; curating is harmless and uniform.
section "niri curated session"
install -d "${ROOT}${WAYLAND_SESSIONS_DIR}"
ln -sf /usr/share/wayland-sessions/niri.desktop \
  "${ROOT}${WAYLAND_SESSIONS_DIR}/niri.desktop"

# =============================================================================
# NOCTALIA WORK PRESET (ADR 0090/0097) — wayland_shell=noctalia only
# =============================================================================
# Bare niri (none / unset) stops at the core above — the operator's dotfiles own
# the shell. Under noctalia, hand off to the shared preset module: map this
# adapter's seams onto the module's NOC_* contract, pick the niri config file and
# the niri plugin slice, and let the module install + seed + vendor.
if [[ "${ENVIRONMENT_WAYLAND_SHELL:-}" == noctalia ]]; then
  # NOC_* are the shared preset module's input contract (read by
  # lib/chroot/noctalia-preset.sh, sourced above) — exported so the contract is
  # explicit and to satisfy the same-shell reader.
  export NOC_JSON="$NIRI_JSON"
  export NOC_SEED_ROOT="$SEED_ROOT"
  export NOC_CURATED_DIR="$NIRI_CURATED_DIR"
  export NOC_BAT_GLOB="${NIRI_BAT_GLOB:-/sys/class/power_supply/BAT*}"
  export NOC_SLICE_FN=noctalia_niri_plugins
  noctalia_preset_install ".config/niri/config.kdl" ".config/niri/config.kdl"
fi

section "niri installation complete"
