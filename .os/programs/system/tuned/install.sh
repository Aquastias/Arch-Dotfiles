#!/usr/bin/env bash
# =============================================================================
# programs/system/tuned/install.sh
# =============================================================================
# Invoked by .os/lib/profiles/runner.sh inside arch-chroot, as root.
# Env vars provided by the runner: OS_DIR, PROGRAMS, SHELL_COMMONS.
#
# Installs tuned and tuned-ppd and enables tuned.service so tunable power
# profiles are active on first boot. tuned-ppd re-exposes the power-profiles-
# daemon D-Bus interface, so KDE Powerdevil / a Hyprland applet still show a
# working profile switcher; tuned-adm drives it headlessly.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[tuned] error on line $LINENO" >&2' ERR

print_status info "Installing tuned + tuned-ppd..."
pacman -S --noconfirm --needed tuned tuned-ppd

print_status info "Enabling tuned.service..."
systemctl enable tuned.service

print_status success "tuned staged."
