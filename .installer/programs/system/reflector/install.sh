#!/usr/bin/env bash
# =============================================================================
# programs/system/reflector/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as root.
# Env vars provided by the runner: INSTALLER_DIR, PROGRAMS, SHELL_COMMONS.
#
# Installs reflector; the runner enables reflector.timer (declared in
# config.jsonc system_services) for a weekly mirror-list refresh using the
# package's default /etc/xdg/reflector/reflector.conf (Arch Wiki: Reflector).
# =============================================================================

set -Eeuo pipefail
trap 'echo "[reflector] error on line $LINENO" >&2' ERR

print_status info "Installing reflector..."
pacman -S --noconfirm --needed reflector

print_status success "reflector staged." \
  "reflector.timer refreshes mirrors weekly."
