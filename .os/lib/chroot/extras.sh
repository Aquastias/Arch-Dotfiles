#!/usr/bin/env bash
# lib/chroot/extras.sh — Chroot Configuration Module:
# optional post-install scripts
# Runs inside arch-chroot.
# ENVIRONMENT_DESKTOP: space-separated list of desktop environments to install.
#   Passed as env var from the host into the chroot.
# STATE and EXTRAS_DIR are injectable for tests.
set -Eeuo pipefail
trap 'echo "[chroot:extras] failed at line $LINENO" >&2' ERR

EXTRAS_DIR="${EXTRAS_DIR:-/root/extras}"

# shellcheck source=./install-state.sh
STATE="${STATE:-/root/lib-chroot/install-state.json}"
_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
_INSTALL_STATE_SH="$_LIB_DIR/install-state.sh"
[[ -f "$_INSTALL_STATE_SH" ]] || _INSTALL_STATE_SH="$_LIB_DIR/../install-state.sh"
# shellcheck disable=SC1090
source "$_INSTALL_STATE_SH"
install_state_load "$STATE"

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

if [[ "$EXTRAS_BACKUP" == "true" ]]; then
  if [[ -f "${EXTRAS_DIR}/backup.sh" ]]; then
    bash "${EXTRAS_DIR}/backup.sh"
  else
    echo "[WARN] backup enabled but ${EXTRAS_DIR}/backup.sh" \
         "not found — skipping."
  fi
fi

if [[ "$EXTRAS_SECURITY" == "true" ]]; then
  if [[ -f "${EXTRAS_DIR}/security.sh" ]]; then
    bash "${EXTRAS_DIR}/security.sh"
  else
    echo "[WARN] security enabled but ${EXTRAS_DIR}/security.sh" \
         "not found — skipping."
  fi
fi
