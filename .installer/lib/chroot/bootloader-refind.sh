#!/usr/bin/env bash
# lib/chroot/bootloader-refind.sh — Bootloader Adapter: rEFInd (ADR 0077/0078)
# Runs inside arch-chroot. An ESP-mirroring loader: refind autodetects the
# vmlinuz-* the ESP Kernel Sync mirrors onto the FAT ESP, so multi-kernel is
# free — this adapter installs refind, gives the cmdline via refind_linux.conf,
# and pins the default selection to the Primary Kernel.
# NOTE: not exercised by unit tests; VM-matrix validated (the pure entry text is
# tested via lib/boot/loader-entries.sh).
set -Eeuo pipefail
_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=./chroot-common.sh
source "$_LIB_DIR/chroot-common.sh"
chroot_err_trap "bootloader-refind"

# bootloader-common sources install-state + loads STATE, then the kernel /
# microcode / zswap / entry libs and computes the shared per-boot values.
STATE="${STATE:-/root/lib-chroot/install-state.json}"
# shellcheck source=./bootloader-common.sh
source "$_LIB_DIR/bootloader-common.sh"

# Install refind onto the ESP and register its UEFI entry (uses efibootmgr).
refind-install --root / 2>&1 | grep -v "world accessible" || true

# Mirror every selected kernel's images onto the ESP; refind autodetects them.
for _tok in "${KERNELS[@]}"; do
  blcommon_stage_kernel "$(kernel_pkg "$_tok")" >/dev/null
done
blcommon_stage_microcode

# refind_linux.conf beside the kernels supplies the boot options for every
# autodetected vmlinuz-*; refind pairs each with its initramfs + *-ucode.img.
refind_linux_conf "$DEFAULT_OPTS" > "$ESP/refind_linux.conf"

# Pin the default menu selection to the Primary Kernel image.
REFIND_CONF="$ESP/EFI/refind/refind.conf"
if [[ -f "$REFIND_CONF" ]]; then
  printf 'default_selection "vmlinuz-%s"\n' "$PRIMARY_KBASE" >> "$REFIND_CONF"
fi

blcommon_install_esp_sync_hooks
echo "rEFInd installed."
