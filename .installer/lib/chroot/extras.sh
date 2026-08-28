#!/usr/bin/env bash
# lib/chroot/extras.sh — Chroot Configuration Module:
# the Environment Runner (desktop adapters).
# Runs inside arch-chroot.
# ENVIRONMENT_DESKTOP: space-separated list of desktop environments to install.
#   Passed as env var from the host into the chroot.
# EXTRAS_DIR is injectable for tests.
#
# Security & Backup Extras are no longer dispatched here: they install via the
# Primary User's paru pass in the Profiles Runner (ADR 0041), not as root-level
# chroot scripts. The old backup.sh / security.sh dispatch (which pointed at
# scripts that were never shipped) is gone.
set -Eeuo pipefail
# shellcheck source=./chroot-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/chroot-common.sh"
chroot_err_trap "extras"

EXTRAS_DIR="${EXTRAS_DIR:-/root/extras}"

# Environment Runner: dispatch to desktop/<de>/<de>.sh for each selected DE.
read -ra _desktops <<< "${ENVIRONMENT_DESKTOP:-}"
for _de in "${_desktops[@]}"; do
  _adapter="${EXTRAS_DIR}/desktop/${_de}/${_de}.sh"
  if [[ ! -f "$_adapter" ]]; then
    echo "[ERROR] No adapter found for desktop '${_de}': ${_adapter}" >&2
    exit 1
  fi
  bash "$_adapter"
done

# Display Manager Adapter (ADR 0069): dispatch the resolved greeter AFTER the
# desktop loop, so every curated session file and seatd the DE adapters write
# already exists. The concrete DM (greetd|sddm|none) is resolved at config load
# and exported as DISPLAY_MANAGER by install_state_load in configure.sh. `none`
# (headless, or auto with no desktop) dispatches nothing. No greeter name is
# hardcoded here — dispatch is purely by directory convention.
_dm="${DISPLAY_MANAGER:-none}"
if [[ -n "$_dm" && "$_dm" != "none" ]]; then
  _dm_adapter="${EXTRAS_DIR}/dm/${_dm}/${_dm}.sh"
  if [[ ! -f "$_dm_adapter" ]]; then
    echo "[ERROR] No adapter found for display manager '${_dm}':" \
      "${_dm_adapter}" >&2
    exit 1
  fi
  bash "$_dm_adapter"
fi
