#!/usr/bin/env bash
# lib/chroot/bootloader-systemd-boot.sh — Bootloader Adapter: systemd-boot
# Runs inside arch-chroot. An ESP-mirroring loader (ADR 0077/0078): it boots the
# kernels the ESP Kernel Sync mirrors onto the FAT ESP, with a per-kbase default
# + fallback loader entry for every selected kernel and the Primary Kernel as
# the loader default. Shared staging / ESP-sync-hook install live in
# bootloader-common.sh; the pure entry text is tested via loader-entries.sh.
set -Eeuo pipefail
_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=./chroot-common.sh
source "$_LIB_DIR/chroot-common.sh"
chroot_err_trap "bootloader-systemd"

# bootloader-common sources install-state + loads STATE, then the kernel /
# microcode / zswap / entry libs and computes the shared per-boot values.
STATE="${STATE:-/root/lib-chroot/install-state.json}"
# shellcheck source=./bootloader-common.sh
source "$_LIB_DIR/bootloader-common.sh"

# systemd-boot cannot read ZFS — kernel + initramfs live on the FAT32 ESP.
# bootctl warns about "world accessible" / "running in a container" in chroot;
# both are harmless — filter them to keep output clean.
bootctl --esp-path="$ESP" install 2>&1 \
    | grep -v "world accessible\|security hole" \
    | grep -v "running in a container\|skipping EFI" \
    || true

mkdir -p "$ESP/loader/entries"

# loader.conf — default boots the Primary Kernel. editor=yes keeps the boot-time
# cmdline editor available (press 'e') so a broken graphical target is always
# recoverable; systemd-boot force-disables it under Secure Boot regardless.
cat > "$ESP/loader/loader.conf" << EOF
default arch-${PRIMARY_KBASE}.conf
timeout 4
console-mode max
editor yes
EOF

# One default + fallback entry per selected kernel, per-kbase filenames so the
# images never collide on the ESP (ADR 0078). Default entries boot quietly on a
# desktop (clean greeter VT); fallback entries stay verbose for diagnosis.
for _tok in "${KERNELS[@]}"; do
  kbase="$(kernel_pkg "$_tok")"
  fb="$(blcommon_stage_kernel "$kbase")"
  sdboot_entry "Arch Linux (${kbase})" "$kbase" "$MICROCODE_INITRDS" \
    "initramfs-${kbase}.img" \
    "${DEFAULT_OPTS}${QUIET_CMDLINE:+ ${QUIET_CMDLINE}}" \
    > "$ESP/loader/entries/arch-${kbase}.conf"
  if [[ -n "$fb" ]]; then
    sdboot_entry "Arch Linux (${kbase} — fallback)" "$kbase" \
      "$MICROCODE_INITRDS" "$fb" "$DEFAULT_OPTS" \
      > "$ESP/loader/entries/arch-${kbase}-fallback.conf"
  fi
done
blcommon_stage_microcode

blcommon_install_esp_sync_hooks
echo "systemd-boot installed."
