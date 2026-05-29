#!/usr/bin/env bash
# =============================================================================
# programs/office/cups/install.sh
# =============================================================================
# Invoked by .os/lib/profiles.sh inside arch-chroot, as root.
# Env vars provided by the runner: OS_DIR, PROGRAMS, SHELL_COMMONS.
#
# Installs cups and enables cups.service so the print daemon is up on
# first boot independent of any desktop environment selection.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[cups] error on line $LINENO" >&2' ERR

print_status info "Installing cups..."
pacman -S --noconfirm --needed cups

print_status info "Enabling cups.service..."
systemctl enable cups.service

print_status success "cups staged."
