#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$SHELL_COMMONS/commands.sh"
source "$SHELL_COMMONS/permissions.sh"

check_root
check_command "paru"

echo "🔧 Installing AppArmor..."
paru -S --skipreview --noconfirm apparmor

PARAMS_TO_ADD=(
  "apparmor=1"
  "security=apparmor"
  "lsm=landlock,lockdown,yama,integrity,apparmor,bpf"
)

echo "🔧 Updating GRUB_CMDLINE_LINUX_DEFAULT with required parameters..."

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
  echo "Appending required parameters to GRUB_CMDLINE_LINUX_DEFAULT..."
  sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"|GRUB_CMDLINE_LINUX_DEFAULT=\"$new_cmdline\"|" "$GRUB_DEFAULT_FILE"
else
  echo "All required parameters already present in GRUB_CMDLINE_LINUX_DEFAULT."
fi

echo "🔧 Regenerating GRUB configuration at $GRUB_BOOT_CFG..."
grub-mkconfig -o "$GRUB_BOOT_CFG"

echo "🔧 Enabling and starting AppArmor service..."
systemctl enable --now apparmor.service

echo "🔧 Verifying AppArmor status..."
aa-status || echo "⚠️  Warning: AppArmor may not be fully active until reboot."

echo "✅ AppArmor setup complete. Please reboot to apply kernel parameters."
