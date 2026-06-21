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
trap 'echo "[chroot:extras] failed at line $LINENO" >&2' ERR

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
