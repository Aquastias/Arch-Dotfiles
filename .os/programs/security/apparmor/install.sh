#!/usr/bin/env bash
# =============================================================================
# programs/security/apparmor/install.sh
# =============================================================================
# Invoked by .os/lib/profiles/runner.sh inside arch-chroot, as the owning user, with
# OS_DIR, PROGRAMS, SHELL_COMMONS pre-exported and temp NOPASSWD sudo granted.
#
# Installs apparmor via paru, appends required AppArmor kernel params to the
# active bootloader config (GRUB or systemd-boot), and enables the apparmor
# service. Effective after reboot.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[apparmor] error on line $LINENO" >&2' ERR

GRUB_DEFAULT_FILE="/etc/default/grub"
GRUB_BOOT_CFG="/boot/grub/grub.cfg"
SBOOT_ENTRIES_DIR="/boot/efi/loader/entries"

print_status info "Installing AppArmor..."
paru -S --noconfirm --needed apparmor

PARAMS_TO_ADD=(
  "apparmor=1"
  "security=apparmor"
  "lsm=landlock,lockdown,yama,integrity,apparmor,bpf"
)

_inject_params_into_options_line() {
  local file="$1"
  local current new param
  current=$(grep "^options " "$file" | sed 's/^options //')
  new="$current"
  for param in "${PARAMS_TO_ADD[@]}"; do
    [[ "$new" != *"$param"* ]] && new="$new $param"
  done
  if [[ "$new" != "$current" ]]; then
    sudo sed -i "s|^options .*|options $new|" "$file"
    return 0
  fi
  return 1
}

if [[ -f "$GRUB_DEFAULT_FILE" ]]; then
  print_status info "Updating GRUB_CMDLINE_LINUX_DEFAULT" \
    "with required parameters..."
  current_cmdline=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" \
    "$GRUB_DEFAULT_FILE" | cut -d'"' -f2)
  new_cmdline="$current_cmdline"

  for param in "${PARAMS_TO_ADD[@]}"; do
    [[ "$new_cmdline" != *"$param"* ]] && new_cmdline="$new_cmdline $param"
  done

  if [[ "$new_cmdline" != "$current_cmdline" ]]; then
    print_status info "Appending required parameters to" \
      "GRUB_CMDLINE_LINUX_DEFAULT..."
    sudo sed -i \
      "s|^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"|"\
      "GRUB_CMDLINE_LINUX_DEFAULT=\"$new_cmdline\"|" \
      "$GRUB_DEFAULT_FILE"
  else
    print_status info "All required parameters already present" \
      "in GRUB_CMDLINE_LINUX_DEFAULT."
  fi

  if command -v grub-mkconfig &>/dev/null; then
    print_status info "Regenerating GRUB configuration at $GRUB_BOOT_CFG..."
    sudo grub-mkconfig -o "$GRUB_BOOT_CFG"
  fi
elif [[ -d "$SBOOT_ENTRIES_DIR" ]]; then
  print_status info "systemd-boot detected — patching boot entries" \
    "in $SBOOT_ENTRIES_DIR..."
  patched=0
  while IFS= read -r -d '' entry; do
    if grep -q "^options " "$entry"; then
      if _inject_params_into_options_line "$entry"; then
        print_status info "Patched: $(basename "$entry")"
        (( patched++ )) || true
      else
        print_status info "Already complete: $(basename "$entry")"
      fi
    fi
  done < <(find "$SBOOT_ENTRIES_DIR" -name "*.conf" -print0)
  [[ $patched -eq 0 ]] && \
    print_status info "All entries already had required parameters."
else
  print_status warning "No bootloader config found;" \
    "skipping kernel param injection."
fi

print_status info "Enabling AppArmor service..."
sudo systemctl enable apparmor.service

print_status success "AppArmor staged (active after reboot)."
