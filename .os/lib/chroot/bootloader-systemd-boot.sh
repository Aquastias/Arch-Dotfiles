#!/usr/bin/env bash
# lib/chroot/bootloader-systemd.sh — Bootloader Adapter: systemd-boot
# Runs inside arch-chroot. Reads install-state.json via install-state.sh.
set -Eeuo pipefail
trap 'echo "[chroot:bootloader-systemd] failed at line $LINENO" >&2' ERR

# shellcheck source=./install-state.sh
STATE="${STATE:-/root/lib-chroot/install-state.json}"
_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
_INSTALL_STATE_SH="$_LIB_DIR/install-state.sh"
[[ -f "$_INSTALL_STATE_SH" ]] || _INSTALL_STATE_SH="$_LIB_DIR/../install-state.sh"
# shellcheck disable=SC1090
source "$_INSTALL_STATE_SH"
install_state_load "$STATE"

# Kernel Selection token table — staged next to install-state.sh.
_KERNEL_SH="$_LIB_DIR/kernel.sh"
[[ -f "$_KERNEL_SH" ]] || _KERNEL_SH="$_LIB_DIR/../packages/kernel.sh"
# shellcheck disable=SC1090
source "$_KERNEL_SH"

# Microcode resolution — staged next to kernel.sh; renders entry initrd lines
# from the *-ucode.img actually present in /boot (ADR 0038).
_MICROCODE_SH="$_LIB_DIR/microcode.sh"
[[ -f "$_MICROCODE_SH" ]] || _MICROCODE_SH="$_LIB_DIR/../packages/microcode.sh"
# shellcheck disable=SC1090
source "$_MICROCODE_SH"

# Boot entry tracks the Primary Kernel's package base (interim primary-only
# bridge; secondary kernels still get default presets via mkinitcpio -P).
KBASE="$(kernel_pkg "$KERNEL")"
VMLINUZ="vmlinuz-${KBASE}"
INITRAMFS="initramfs-${KBASE}.img"
INITRAMFS_FB="initramfs-${KBASE}-fallback.img"
ENTRY_TITLE="Arch Linux (ZFS — ${KBASE})"
POOL_ROOT="$RPOOL/ROOT/arch"

# systemd-boot cannot read ZFS — kernel and initramfs must live
# on the FAT32 ESP.
# bootctl warns about "world accessible" and "running in a container" in chroot;
# both are harmless — filter them to keep output clean.
bootctl --esp-path=/boot/efi install 2>&1 \
    | grep -v "world accessible\|security hole" \
    | grep -v "running in a container\|skipping EFI" \
    || true

mkdir -p /boot/efi/loader/entries

cat > /boot/efi/loader/loader.conf << 'EOF'
default arch-zfs.conf
timeout 4
console-mode max
editor no
EOF

# zfs_import_dir=/dev/disk/by-id makes the initramfs ZFS hook import by scanning
# stable by-id paths instead of /etc/zfs/zpool.cache. A stale/corrupt cache then
# cannot brick boot (the hook ignores it when zfs_import_dir is set).
# Render microcode initrd lines from the *-ucode.img present in /boot, so an
# entry never references a missing initrd (ADR 0038).
MICROCODE_INITRDS="$(microcode_present_initrds /boot)"

cat > /boot/efi/loader/entries/arch-zfs.conf << EOF
title   ${ENTRY_TITLE}
linux   /${VMLINUZ}
${MICROCODE_INITRDS}
initrd  /${INITRAMFS}
options root=ZFS=${POOL_ROOT} zfs_import_dir=/dev/disk/by-id rw
EOF

cat > /boot/efi/loader/entries/arch-zfs-fallback.conf << EOF
title   Arch Linux (ZFS — fallback)
linux   /${VMLINUZ}
${MICROCODE_INITRDS}
initrd  /${INITRAMFS_FB}
options root=ZFS=${POOL_ROOT} zfs_import_dir=/dev/disk/by-id rw
EOF

cp "/boot/${VMLINUZ}"   /boot/efi/
cp "/boot/${INITRAMFS}" /boot/efi/

if [[ ! -f "/boot/${INITRAMFS_FB}" ]]; then
    echo "Fallback initramfs not found — generating now ..."
    mkinitcpio -p "$KBASE" -S autodetect 2>/dev/null \
        || mkinitcpio -g "/boot/${INITRAMFS_FB}" 2>/dev/null \
        || true
fi
if [[ -f "/boot/${INITRAMFS_FB}" ]]; then
    cp "/boot/${INITRAMFS_FB}" /boot/efi/
else
    rm -f /boot/efi/loader/entries/arch-zfs-fallback.conf
    echo "Note: fallback initramfs not available — fallback boot entry removed."
fi

[[ -f /boot/intel-ucode.img ]] && cp /boot/intel-ucode.img /boot/efi/ || true
[[ -f /boot/amd-ucode.img   ]] && cp /boot/amd-ucode.img   /boot/efi/ || true

# Pacman hook: keep ESP copies in sync on every kernel transaction. Exec= in a
# pacman hook goes straight to execv (no shell), so it calls a helper script —
# the shared ESP Kernel Sync (lib/boot/esp-kernel-sync.sh), staged into the
# chroot. It mirrors only what the loader entries reference, so a Stray Kernel
# is never copied (ADR 0038).
mkdir -p /etc/pacman.d/hooks
install -Dm755 "$_LIB_DIR/esp-kernel-sync.sh" \
  /usr/local/lib/archzfs/esp-kernel-sync.sh

# Numbered 94 so the ESP Kernel Sync runs BEFORE the ESP Mirror Hook
# (95-esp-mirror), which then rsyncs the freshly-synced primary ESP onto any
# secondary ESPs (ADR 0038).

# 93 (PreTransaction): preflight that aborts the upgrade BEFORE it applies when
# an ESP lacks room for the new boot images, so the system never half-applies
# into a degraded state. AbortOnFail propagates the non-zero exit to pacman.
cat > /etc/pacman.d/hooks/93-esp-kernel-sync-preflight.hook << 'HOOK'
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/lib/modules/*/vmlinuz

[Action]
Description = Checking ESP free space for new boot images...
When = PreTransaction
Exec = /usr/local/lib/archzfs/esp-kernel-sync.sh preflight
AbortOnFail
HOOK

cat > /etc/pacman.d/hooks/94-esp-kernel-sync.hook << 'HOOK'
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/lib/modules/*/vmlinuz

[Action]
Description = Syncing kernel and initramfs to ESP...
When = PostTransaction
Exec = /usr/local/lib/archzfs/esp-kernel-sync.sh
HOOK

echo "systemd-boot installed."
