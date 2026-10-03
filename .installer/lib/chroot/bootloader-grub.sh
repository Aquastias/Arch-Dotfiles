#!/usr/bin/env bash
# lib/chroot/bootloader-grub.sh — Bootloader Adapter: GRUB
# Dispatched by configure.sh inside arch-chroot when options.bootloader=grub.
# GRUB cannot read the rpool (native encryption, features beyond grub2), so it
# boots like limine: kernels staged on the ESP, its modules and a rendered
# grub.cfg there too, no grub-mkconfig (it probes the ZFS root) (ADR 0078).
set -Eeuo pipefail
_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=./chroot-common.sh
source "$_LIB_DIR/chroot-common.sh"
chroot_err_trap "bootloader-grub"

STATE="${STATE:-/root/lib-chroot/install-state.json}"
# shellcheck source=./bootloader-common.sh
source "$_LIB_DIR/bootloader-common.sh"

pacman -S --noconfirm --needed grub

# --boot-directory on the ESP puts the prefix (and so GRUB's root) there.
# --removable also writes EFI/BOOT/BOOTX64.EFI, which laptop firmware that
# forgets NVRAM entries still boots.
grub-install --target=x86_64-efi --efi-directory="$ESP" \
  --boot-directory="$ESP" --bootloader-id=GRUB --recheck --removable

# Primary Kernel first: default=0 is the pin a Stray Kernel cannot take
# (ADR 0038).
CONF="$ESP/grub/grub.cfg"
printf 'set timeout=4\nset default=0\n\n' > "$CONF"
_ordered=("$PRIMARY_KBASE")
for _tok in "${KERNELS[@]}"; do
  _kb="$(kernel_pkg "$_tok")"
  [[ "$_kb" == "$PRIMARY_KBASE" ]] || _ordered+=("$_kb")
done
for _kb in "${_ordered[@]}"; do
  _fb="$(blcommon_stage_kernel "$_kb")"
  grub_entry "Arch Linux (${_kb})" "$_kb" "$MICROCODE_IMGS" \
    "initramfs-${_kb}.img" "$DEFAULT_OPTS" >> "$CONF"
  if [[ -n "$_fb" ]]; then
    grub_entry "Arch Linux (${_kb} — fallback)" "$_kb" "$MICROCODE_IMGS" \
      "$_fb" "$DEFAULT_OPTS" >> "$CONF"
  fi
done
blcommon_stage_microcode
blcommon_install_esp_sync_hooks
echo "GRUB installed (kernels + grub.cfg on the ESP)."
