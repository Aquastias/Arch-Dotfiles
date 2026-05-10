#!/usr/bin/env bash
# lib/chroot/bootloader-systemd.sh — Bootloader Adapter: systemd-boot
# Runs inside arch-chroot. Reads install-state.json via load-state.sh.
set -Eeuo pipefail
trap 'echo "[chroot:bootloader-systemd] failed at line $LINENO" >&2' ERR

# shellcheck source=./load-state.sh
source "$(dirname "${BASH_SOURCE[0]}")/load-state.sh"

if [[ "$KERNEL" == "lts" ]]; then
    VMLINUZ="vmlinuz-linux-lts"
    INITRAMFS="initramfs-linux-lts.img"
    INITRAMFS_FB="initramfs-linux-lts-fallback.img"
    ENTRY_TITLE="Arch Linux (ZFS — linux-lts)"
else
    VMLINUZ="vmlinuz-linux"
    INITRAMFS="initramfs-linux.img"
    INITRAMFS_FB="initramfs-linux-fallback.img"
    ENTRY_TITLE="Arch Linux (ZFS)"
fi
POOL_ROOT="$RPOOL/ROOT/arch"

# systemd-boot cannot read ZFS — kernel and initramfs must live on the FAT32 ESP.
# bootctl warns about "world accessible" and "running in a container" in chroot;
# both are harmless — filter them to keep output clean.
bootctl --esp-path=/boot/efi install 2>&1 \
    | grep -v "world accessible\|security hole\|running in a container\|skipping EFI" \
    || true

mkdir -p /boot/efi/loader/entries

cat > /boot/efi/loader/loader.conf << 'EOF'
default arch-zfs.conf
timeout 4
console-mode max
editor no
EOF

cat > /boot/efi/loader/entries/arch-zfs.conf << EOF
title   ${ENTRY_TITLE}
linux   /${VMLINUZ}
initrd  /intel-ucode.img
initrd  /amd-ucode.img
initrd  /${INITRAMFS}
options root=ZFS=${POOL_ROOT} rw
EOF

cat > /boot/efi/loader/entries/arch-zfs-fallback.conf << EOF
title   Arch Linux (ZFS — fallback)
linux   /${VMLINUZ}
initrd  /intel-ucode.img
initrd  /amd-ucode.img
initrd  /${INITRAMFS_FB}
options root=ZFS=${POOL_ROOT} rw
EOF

cp "/boot/${VMLINUZ}"   /boot/efi/
cp "/boot/${INITRAMFS}" /boot/efi/

if [[ ! -f "/boot/${INITRAMFS_FB}" ]]; then
    echo "Fallback initramfs not found — generating now ..."
    mkinitcpio -p "linux-${KERNEL/default/}" -S autodetect 2>/dev/null \
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

# Pacman hook: keep ESP copies in sync on every kernel upgrade.
# Exec= in a pacman hook goes directly to execv — no shell syntax allowed.
# Write a helper script and call that.
mkdir -p /etc/pacman.d/hooks /usr/local/lib/archzfs

cat > /usr/local/lib/archzfs/esp-kernel-sync.sh << 'SCRIPT'
#!/usr/bin/env bash
for f in /boot/vmlinuz-linux* /boot/initramfs-linux*.img \
          /boot/intel-ucode.img /boot/amd-ucode.img; do
    [[ -f "$f" ]] || continue
    cp "$f" /boot/efi/
    for d in /boot/efi*/; do
        [[ "$d" != "/boot/efi/" ]] && cp "$f" "$d"
    done
done
SCRIPT
chmod +x /usr/local/lib/archzfs/esp-kernel-sync.sh

cat > /etc/pacman.d/hooks/96-esp-kernel-sync.hook << 'HOOK'
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
