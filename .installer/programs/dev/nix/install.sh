#!/usr/bin/env bash
# =============================================================================
# programs/dev/nix/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as root.
# Env vars provided by the runner: INSTALLER_DIR, PROGRAMS, SHELL_COMMONS.
#
# Installs nix; the runner enables nix-daemon.service (Arch Wiki: Nix). The
# store directory is created by a tmpfiles rule (here and on every boot):
# user-side tools open /nix/store before talking to the daemon.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[nix] error on line $LINENO" >&2' ERR

print_status info "Installing nix..."
pacman -S --noconfirm --needed nix

print_status info "Creating the Nix store (tmpfiles)..."
printf '%s\n' '# Nix store root; the package does not create it.' \
  'd /nix/store 1775 root nixbld -' > /etc/tmpfiles.d/nix-store.conf
systemd-tmpfiles --create /etc/tmpfiles.d/nix-store.conf

print_status success "nix staged." "nix-daemon starts on boot; add a channel" \
  "to use <nixpkgs>."
