#!/usr/bin/env bash
# =============================================================================
# programs/system/bluetooth/install.sh
# =============================================================================
# Invoked by .os/lib/profiles/runner.sh inside arch-chroot, as root.
# Env vars provided by the runner: OS_DIR, PROGRAMS, SHELL_COMMONS.
#
# Installs bluez + bluez-utils and enables bluetooth.service so the Bluetooth
# daemon is up on first boot independent of any desktop environment. bluez-utils
# provides bluetoothctl — the headless/non-KDE control path. On KDE bluez
# already arrives via plasma-meta, so the install is a --needed no-op there and
# the material effect is the service enable (nothing else does it). The GUI tray
# is the desktop's concern (BlueDevil on KDE; blueman on Hyprland), never here.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[bluetooth] error on line $LINENO" >&2' ERR

print_status info "Installing bluez + bluez-utils..."
pacman -S --noconfirm --needed bluez bluez-utils

print_status info "Enabling bluetooth.service..."
systemctl enable bluetooth.service

print_status success "bluetooth staged."
