#!/usr/bin/env bash
# =============================================================================
# programs/power/power-profiles-daemon/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as root.
# Env vars provided by the runner: INSTALLER_DIR, PROGRAMS, SHELL_COMMONS.
#
# Installs power-profiles-daemon and enables its service so power-profile
# switching (performance / balanced / power-saver) works on first boot. It is
# only an optional dep of Powerdevil, so this genuinely adds it even on KDE;
# DE-agnostic — powerprofilesctl drives it without any desktop.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[power-profiles-daemon] error on line $LINENO" >&2' ERR

print_status info "Installing power-profiles-daemon..."
pacman -S --noconfirm --needed power-profiles-daemon

print_status info "Enabling power-profiles-daemon.service..."
systemctl enable power-profiles-daemon.service

print_status success "power-profiles-daemon staged."
