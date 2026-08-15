#!/usr/bin/env bash
# lib/chroot/bootloader-limine.sh — Bootloader Adapter: Limine (ADR 0077/0078)
# Runs inside arch-chroot. An ESP-mirroring loader: it boots the kernels the ESP
# Kernel Sync mirrors onto the FAT ESP, driven by a generated limine.conf with a
# per-kernel entry (default first) + a fallback entry each. The Primary Kernel's
# entry is listed first, so it is the default.
# NOTE: not exercised by unit tests; VM-matrix validated (the pure limine.conf
# entry text is tested via lib/boot/loader-entries.sh).
set -Eeuo pipefail
_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=./chroot-common.sh
source "$_LIB_DIR/chroot-common.sh"
chroot_err_trap "bootloader-limine"

# bootloader-common sources install-state + loads STATE, then the kernel /
# microcode / zswap / entry libs and computes the shared per-boot values.
STATE="${STATE:-/root/lib-chroot/install-state.json}"
# shellcheck source=./bootloader-common.sh
source "$_LIB_DIR/bootloader-common.sh"

# Deploy the limine EFI binary onto the ESP and register its UEFI entry.
mkdir -p "$ESP/EFI/limine"
cp /usr/share/limine/BOOTX64.EFI "$ESP/EFI/limine/limine_x64.efi"
_efi_dev="$(findmnt -n -o SOURCE "$ESP")"
_efi_disk="${_efi_dev%p[0-9]*}"; _efi_disk="${_efi_disk%[0-9]*}"
efibootmgr --create --disk "$_efi_disk" --part 1 --label "Limine" \
  --loader '\EFI\limine\limine_x64.efi' --unicode || true

# Generate limine.conf: the Primary Kernel first (default), each kernel's
# default + fallback entry. Mirror every kernel's images onto the ESP.
CONF="$ESP/limine.conf"
printf 'timeout: 4\n\n' > "$CONF"
_ordered=("$PRIMARY_KBASE")
for _tok in "${KERNELS[@]}"; do
  _kb="$(kernel_pkg "$_tok")"
  [[ "$_kb" == "$PRIMARY_KBASE" ]] || _ordered+=("$_kb")
done
for _kb in "${_ordered[@]}"; do
  _fb="$(blcommon_stage_kernel "$_kb")"
  limine_entry "Arch Linux (${_kb})" "$_kb" "$MICROCODE_INITRDS" \
    "initramfs-${_kb}.img" "$DEFAULT_OPTS" >> "$CONF"
  if [[ -n "$_fb" ]]; then
    limine_entry "Arch Linux (${_kb} — fallback)" "$_kb" \
      "$MICROCODE_INITRDS" "$_fb" "$DEFAULT_OPTS" >> "$CONF"
  fi
done
blcommon_stage_microcode

blcommon_install_esp_sync_hooks
echo "Limine installed."
