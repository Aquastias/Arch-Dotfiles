#!/usr/bin/env bash

set -euo pipefail
trap 'echo "Error on line $LINENO"' ERR

# shellcheck source=/dev/null
source "$SHELL_COMMONS/commands.sh"
source "$SHELL_COMMONS/permissions.sh"
source "$SHELL_COMMONS/strings.sh"

check_root
check_command "paru"

print_status info "Installing AppArmor..."
paru -S --skipreview --noconfirm apparmor

PARAMS_TO_ADD=(
  "apparmor=1"
  "security=apparmor"
  "lsm=landlock,lockdown,yama,integrity,apparmor,bpf"
)

print_status info "Updating GRUB_CMDLINE_LINUX_DEFAULT with required parameters..."

# Extract current GRUB_CMDLINE_LINUX_DEFAULT value
current_cmdline=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_DEFAULT_FILE" | cut -d'"' -f2)

# Initialize new_cmdline with current values
new_cmdline="$current_cmdline"

# Append missing parameters
for param in "${PARAMS_TO_ADD[@]}"; do
  if [[ "$new_cmdline" != *"$param"* ]]; then
    new_cmdline="$new_cmdline $param"
  fi
done

# Update GRUB config only if changes are needed
if [[ "$new_cmdline" != "$current_cmdline" ]]; then
  print_status info "Appending required parameters to GRUB_CMDLINE_LINUX_DEFAULT..."
  sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"|GRUB_CMDLINE_LINUX_DEFAULT=\"$new_cmdline\"|" "$GRUB_DEFAULT_FILE"
else
  print_status info "All required parameters already present in GRUB_CMDLINE_LINUX_DEFAULT."
fi

print_status info "Regenerating GRUB configuration at $GRUB_BOOT_CFG..."
grub-mkconfig -o "$GRUB_BOOT_CFG"

print_status info "Enabling and starting AppArmor service..."
systemctl enable --now apparmor.service

print_status info "Verifying AppArmor status..."
aa-status || print_status warning "AppArmor may not be fully active until reboot."

print_status success "AppArmor setup complete. Please reboot to apply kernel parameters."
