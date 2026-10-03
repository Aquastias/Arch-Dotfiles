#!/usr/bin/env bash
# =============================================================================
# programs/bootloader/grub/install.sh
# =============================================================================
# Invoked by lib/profiles/runner.sh inside arch-chroot, as root, via
# run-program.sh (which sources Shell Stdlib first, providing print_status).
#
# The bootloader adapter (lib/chroot/bootloader-grub.sh) owns GRUB: it boots
# from the ESP with a rendered grub.cfg, since GRUB cannot read the rpool
# (ADR 0078). This program only ensures the package and that the adapter ran.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[grub] error on line $LINENO" >&2' ERR

pacman -S --noconfirm --needed grub
if [[ -s /boot/efi/grub/grub.cfg ]]; then
  print_status success "grub present (ESP grub.cfg from the adapter)."
else
  print_status warning "grub installed but not the bootloader:" \
    "set options.bootloader=grub to boot with it."
fi
