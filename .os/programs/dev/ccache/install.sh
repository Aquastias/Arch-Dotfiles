#!/usr/bin/env bash
# =============================================================================
# programs/dev/ccache/install.sh
# =============================================================================
# Invoked by .os/lib/profiles/runner.sh inside arch-chroot, as root.
# Env vars provided by the runner: OS_DIR, PROGRAMS, SHELL_COMMONS.
#
# Installs ccache and enables the ccache BUILDENV flag in /etc/makepkg.conf
# (!ccache → ccache) so makepkg / paru cache compilations for faster rebuilds
# (Arch Wiki: Ccache). Idempotent: the substitution is a no-op once enabled.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[ccache] error on line $LINENO" >&2' ERR

print_status info "Installing ccache..."
pacman -S --noconfirm --needed ccache

if grep -q '^BUILDENV=.*!ccache' /etc/makepkg.conf; then
  print_status info "Enabling ccache in /etc/makepkg.conf BUILDENV..."
  sed -i 's/!ccache/ccache/' /etc/makepkg.conf
else
  print_status info "ccache already enabled in /etc/makepkg.conf BUILDENV."
fi

print_status success "ccache staged."
