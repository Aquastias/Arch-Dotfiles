#!/usr/bin/env bash
# =============================================================================
# programs/system/smartmontools/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as root.
# Env vars provided by the runner: INSTALLER_DIR, PROGRAMS, SHELL_COMMONS.
#
# Installs smartmontools; the runner enables smartd.service (declared in
# config.jsonc system_services) so disk SMART health is monitored from first
# boot using the shipped /etc/smartd.conf DEVICESCAN default (Arch Wiki:
# S.M.A.R.T.).
# =============================================================================

set -Eeuo pipefail
trap 'echo "[smartmontools] error on line $LINENO" >&2' ERR

print_status info "Installing smartmontools..."
pacman -S --noconfirm --needed smartmontools

print_status success "smartmontools staged." \
  "smartd.service monitors disk SMART health at boot."
