#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$SHELL_COMMONS/commands.sh"
source "$SHELL_COMMONS/permissions.sh"
source "$SHELL_COMMONS/strings.sh"

check_root
check_command "paru"

print_status info "Installing grub and required tools..."
paru -S --skipreview --noconfirm grub os-prober

if [[ -f "$GRUB_DEFAULT_FILE" ]]; then
  if grep -q '^#\s*GRUB_DISABLE_OS_PROBER=' "$GRUB_DEFAULT_FILE"; then
    sed -i 's/^#\s*\(GRUB_DISABLE_OS_PROBER=\).*/\1false/' "$GRUB_DEFAULT_FILE"
  elif grep -q '^GRUB_DISABLE_OS_PROBER=' "$GRUB_DEFAULT_FILE"; then
    sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' "$GRUB_DEFAULT_FILE"
  else
    echo 'GRUB_DISABLE_OS_PROBER=false' >>"$GRUB_DEFAULT_FILE"
  fi

  print_status success "os-prober enabled in $GRUB_DEFAULT_FILE"
else
  print_status error "$GRUB_DEFAULT_FILE not found"
  exit 1
fi

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck --removable
grub-mkconfig -o "$GRUB_BOOT_CFG"
