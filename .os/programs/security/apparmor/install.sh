#!/usr/bin/env bash
# =============================================================================
# programs/security/apparmor/install.sh
# =============================================================================
# Invoked by .os/lib/profiles.sh inside arch-chroot, as the owning user, with
# OS_DIR, PROGRAMS, SHELL_COMMONS pre-exported and temp NOPASSWD sudo granted.
#
# Installs apparmor via paru, appends required AppArmor kernel params to
# GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub, regenerates grub.cfg, and
# enables the apparmor service. Effective after reboot.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[apparmor] error on line $LINENO" >&2' ERR

GRUB_DEFAULT_FILE="/etc/default/grub"
GRUB_BOOT_CFG="/boot/grub/grub.cfg"

print_status info "Installing AppArmor..."
paru -S --noconfirm --needed --skipreview apparmor

PARAMS_TO_ADD=(
  "apparmor=1"
  "security=apparmor"
  "lsm=landlock,lockdown,yama,integrity,apparmor,bpf"
)

print_status info "Updating GRUB_CMDLINE_LINUX_DEFAULT with required parameters..."
current_cmdline=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_DEFAULT_FILE" | cut -d'"' -f2)
new_cmdline="$current_cmdline"

for param in "${PARAMS_TO_ADD[@]}"; do
  if [[ "$new_cmdline" != *"$param"* ]]; then
    new_cmdline="$new_cmdline $param"
  fi
done

if [[ "$new_cmdline" != "$current_cmdline" ]]; then
  print_status info "Appending required parameters to GRUB_CMDLINE_LINUX_DEFAULT..."
  sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"|GRUB_CMDLINE_LINUX_DEFAULT=\"$new_cmdline\"|" "$GRUB_DEFAULT_FILE"
else
  print_status info "All required parameters already present in GRUB_CMDLINE_LINUX_DEFAULT."
fi

if command -v grub-mkconfig &>/dev/null; then
  print_status info "Regenerating GRUB configuration at $GRUB_BOOT_CFG..."
  sudo grub-mkconfig -o "$GRUB_BOOT_CFG"
fi

print_status info "Enabling AppArmor service..."
sudo systemctl enable apparmor.service

print_status success "AppArmor staged (active after reboot)."
