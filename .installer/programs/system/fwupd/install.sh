#!/usr/bin/env bash
# =============================================================================
# programs/system/fwupd/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as root.
# Env vars provided by the runner: INSTALLER_DIR, PROGRAMS, SHELL_COMMONS.
#
# Installs fwupd; the runner enables fwupd-refresh.timer (declared in
# config.jsonc system_services) for periodic firmware metadata refresh and MOTD
# update notices — not enabled by default on Arch (Arch Wiki: fwupd).
# =============================================================================

set -Eeuo pipefail
trap 'echo "[fwupd] error on line $LINENO" >&2' ERR

print_status info "Installing fwupd..."
pacman -S --noconfirm --needed fwupd

print_status success "fwupd staged." \
  "fwupd-refresh.timer refreshes firmware metadata."
