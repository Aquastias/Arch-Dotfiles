#!/usr/bin/env bash
# =============================================================================
# programs/bootloader/grub/install.sh
# =============================================================================
# Invoked by .os/lib/profiles.sh inside arch-chroot, as root.
# Env vars provided by the runner: OS_DIR, PROGRAMS, SHELL_COMMONS.
#
# Installs grub + os-prober via pacman, flips GRUB_DISABLE_OS_PROBER=false in
# /etc/default/grub, runs grub-install for x86_64-efi, and regenerates the
# grub config. Mirrors .pkglist/programs/bootloader/grub/install.sh but uses
# pacman (paru is not available during the system-program phase) and pins
# the canonical grub paths instead of relying on undefined env vars.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[grub] error on line $LINENO" >&2' ERR

GRUB_DEFAULT_FILE="/etc/default/grub"
GRUB_BOOT_CFG="/boot/grub/grub.cfg"

print_status info "Installing grub and os-prober..."
pacman -S --noconfirm --needed grub os-prober

if [[ -f "$GRUB_DEFAULT_FILE" ]]; then
  if grep -q '^#\s*GRUB_DISABLE_OS_PROBER=' "$GRUB_DEFAULT_FILE"; then
    sed -i 's/^#\s*\(GRUB_DISABLE_OS_PROBER=\).*/\1false/' "$GRUB_DEFAULT_FILE"
  elif grep -q '^GRUB_DISABLE_OS_PROBER=' "$GRUB_DEFAULT_FILE"; then
    sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' "$GRUB_DEFAULT_FILE"
  else
    echo 'GRUB_DISABLE_OS_PROBER=false' >>"$GRUB_DEFAULT_FILE"
  fi
  print_status success "os-prober enabled in $GRUB_DEFAULT_FILE."
else
  print_status error "$GRUB_DEFAULT_FILE not found."
  exit 1
fi

print_status info "Installing GRUB EFI binary..."
grub-install \
  --target=x86_64-efi \
  --efi-directory=/boot \
  --bootloader-id=GRUB \
  --recheck \
  --removable

print_status info "Regenerating GRUB configuration at $GRUB_BOOT_CFG..."
grub-mkconfig -o "$GRUB_BOOT_CFG"

print_status success "grub installed and configured."
