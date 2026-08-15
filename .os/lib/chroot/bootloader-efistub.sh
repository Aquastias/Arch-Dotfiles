#!/usr/bin/env bash
# lib/chroot/bootloader-efistub.sh — Bootloader Adapter: EFISTUB (ADR 0077/0078)
# Runs inside arch-chroot. A direct-UEFI boot method (not a loader binary): it
# registers one efibootmgr entry per selected kernel + a fallback entry, each
# pointing at the ESP-mirrored kernel with initrd + cmdline load-options. The
# Primary Kernel boots by default (registered last → first in BootOrder). The
# secondary-ESP loop in configure.sh reuses blcommon_efistub_register so every
# OS disk carries the same entries.
# NOTE: not exercised by unit tests; VM-matrix validated (the pure load-options
# string is tested via lib/boot/loader-entries.sh).
set -Eeuo pipefail
_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=./chroot-common.sh
source "$_LIB_DIR/chroot-common.sh"
chroot_err_trap "bootloader-efistub"

# bootloader-common sources install-state + loads STATE, then the kernel /
# microcode / zswap / entry libs and computes the shared per-boot values.
STATE="${STATE:-/root/lib-chroot/install-state.json}"
# shellcheck source=./bootloader-common.sh
source "$_LIB_DIR/bootloader-common.sh"

# Mirror every selected kernel's images onto the ESP (the "loader" is the kernel
# itself), then the microcode.
for _tok in "${KERNELS[@]}"; do
  blcommon_stage_kernel "$(kernel_pkg "$_tok")" >/dev/null
done
blcommon_stage_microcode

# Resolve the primary ESP's disk + partition for efibootmgr, then register the
# per-kernel entries. nvme/mmc use a `p<N>` partition suffix, sata does not.
EFI_DEV="$(findmnt -n -o SOURCE "$ESP")"
if [[ "$EFI_DEV" =~ nvme|mmcblk ]]; then
  EFI_DISK="${EFI_DEV%p[0-9]*}"; EFI_PART="${EFI_DEV##*p}"
else
  EFI_DISK="${EFI_DEV%[0-9]*}"; EFI_PART="${EFI_DEV##*[a-z]}"
fi
blcommon_efistub_register "$EFI_DISK" "$EFI_PART" ""

blcommon_install_esp_sync_hooks
echo "EFISTUB installed."
