#!/usr/bin/env bash
# lib/chroot/bootloader-efistub.sh — Bootloader Adapter: EFISTUB (ADR 0077/0078)
# Runs inside arch-chroot. A direct-UEFI boot method (not a loader binary): it
# registers one efibootmgr entry per selected kernel + a fallback entry, each
# pointing at the ESP-mirrored kernel with initrd + cmdline load-options. The
# Primary Kernel boots by default (registered last → first in BootOrder). The
# secondary-ESP loop in configure.sh reuses bootloader_common_efistub_register
# so every OS disk carries the same entries. NOTE: not exercised by unit tests;
# VM-matrix validated (the pure load-options string is tested via
# lib/boot/loader-entries.sh).
set -Eeuo pipefail
# Like dirname: a path with no slash means the current directory.
_LIB_DIR="${BASH_SOURCE[0]%/*}"
[[ "$_LIB_DIR" != "${BASH_SOURCE[0]}" ]] || _LIB_DIR=.
# shellcheck source=./chroot-common.sh
source "$_LIB_DIR/chroot-common.sh"
chroot_error_trap "bootloader-efistub"

# bootloader-common sources install-state + loads STATE, then the kernel /
# microcode / zswap / entry libs and computes the shared per-boot values.
STATE="${STATE:-/root/lib-chroot/install-state.json}"
# shellcheck source=./bootloader-common.sh
source "$_LIB_DIR/bootloader-common.sh"

# Mirror every selected kernel's images onto the ESP (the "loader" is the kernel
# itself), then the microcode.
for _kernel in "${KERNELS[@]}"; do
  bootloader_common_stage_kernel "$(kernel_package "$_kernel")" >/dev/null
done
bootloader_common_stage_microcode

# Resolve the primary ESP's disk + partition, then register the per-kernel
# entries against it.
read -r EFI_DISK EFI_PART < <(bootloader_common_esp_disk_partition)
bootloader_common_efistub_register "$EFI_DISK" "$EFI_PART" ""

bootloader_common_install_esp_sync_hooks
echo "EFISTUB installed."
