#!/usr/bin/env bash
# =============================================================================
# programs/security/apparmor/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as the owning user, with
# INSTALLER_DIR, PROGRAMS, SHELL_COMMONS pre-exported and temp NOPASSWD sudo
# granted.
#
# Installs apparmor and enables the apparmor service (loads the profiles at
# boot). The `lsm=` kernel parameter it needs is installer-owned: every
# Bootloader Adapter appends it when AppArmor is selected (lib/boot/lsm.sh),
# so all five loaders carry it. Effective after reboot.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[apparmor] error on line $LINENO" >&2' ERR

print_status info "Installing AppArmor..."
${AUR_HELPER} -S --noconfirm --needed apparmor

print_status info "Enabling AppArmor service..."
sudo systemctl enable apparmor.service

print_status success "AppArmor staged (active after reboot)."
