#!/usr/bin/env bash
# lib/chroot/configure.sh — Chroot Configuration Module: orchestrator
# Entry point run by configure_system() via:
#   ROOT_PW="<pw>" arch-chroot /mnt bash /root/lib-chroot/configure.sh
#
# All non-secret params come from install-state.json (written before arch-chroot).
# ROOT_PW is passed as an env var — never written to disk.
set -Eeuo pipefail
trap 'echo "[chroot:configure] failed at line $LINENO" >&2' ERR

# shellcheck source=./load-state.sh
source "$(dirname "${BASH_SOURCE[0]}")/load-state.sh"

bash /root/lib-chroot/identity.sh
bash /root/lib-chroot/initcpio.sh
bash /root/lib-chroot/bootloader-"$BOOTLOADER".sh

# ── Secondary ESP mirroring ───────────────────────────────────────────────────
# Rsync primary ESP to each secondary, then register each secondary as an
# independent UEFI boot entry so any OS disk can boot if the primary fails.
if [[ "$BOOTLOADER" == "grub" ]]; then
    EFI_LOADER='\EFI\GRUB\grubx64.efi'
else
    EFI_LOADER='\EFI\systemd\systemd-bootx64.efi'
fi
if [[ "$ESP_COUNT" -gt 1 ]]; then
    for i in $(seq 1 $(( ESP_COUNT - 1 ))); do
        rsync -a --delete /boot/efi/ "/boot/efi${i}/"
        EFI_DEV="$(findmnt -n -o SOURCE "/boot/efi${i}" || true)"
        if [[ -n "$EFI_DEV" ]]; then
            [[ "$EFI_DEV" =~ nvme|mmcblk ]] \
                && EFI_DISK="${EFI_DEV%p[0-9]*}" \
                || EFI_DISK="${EFI_DEV%[0-9]*}"
            efibootmgr --create \
                --disk "$EFI_DISK" --part 1 \
                --label "Arch Linux (fallback disk $((i+1)))" \
                --loader "$EFI_LOADER" \
                || true
        fi
    done
fi

# ── Network & time services ───────────────────────────────────────────────────
systemctl enable NetworkManager
systemctl enable systemd-resolved
systemctl enable systemd-timesyncd

# /etc/resolv.conf is bind-mounted in the chroot — can't symlink it here.
# Drop-in + tmpfiles rule create the stub symlink on first real boot.
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/stub.conf << 'EOF'
[Resolve]
DNSStubListener=yes
EOF
mkdir -p /etc/tmpfiles.d
cat > /etc/tmpfiles.d/resolv.conf.conf << 'EOF'
L /etc/resolv.conf - - - - /run/systemd/resolve/stub-resolv.conf
EOF

# ── ZFS services ─────────────────────────────────────────────────────────────
# Import order: zfs-import-cache (fast) → zfs-import-scan (fallback)
#   → zfs-import.target → zfs-mount → zfs-zed → zfs.target
systemctl enable zfs-import-cache
systemctl enable zfs-import-scan
systemctl enable zfs-import.target
systemctl enable zfs-mount
systemctl enable zfs-zed
systemctl enable zfs.target

# Enable per-pool key-load service for any encrypted pools (dpool etc.).
# The initramfs ZFS hook handles the root pool — this covers datasets that
# mount after boot.
if zpool list -H -o name 2>/dev/null | grep -q .; then
    for _pool in $(zpool list -H -o name 2>/dev/null); do
        _enc="$(zfs get -H -o value encryption "${_pool}" 2>/dev/null)"
        if [[ "$_enc" != "off" && "$_enc" != "-" ]]; then
            systemctl enable "zfs-load-key@${_pool}.service" 2>/dev/null || true
        fi
    done
    unset _enc
fi

# Populate zfs-mount-generator cache so datasets mount at boot without scanning.
mkdir -p /etc/zfs/zfs-list.cache
for _pool in $(zpool list -H -o name 2>/dev/null); do
    zfs list -H -t filesystem \
        -o name,mountpoint,canmount,atime,relatime,readonly,xattr,dnodesize \
        "$_pool" 2>/dev/null \
        > "/etc/zfs/zfs-list.cache/${_pool}" || true
done
unset _pool

# ── Swap ─────────────────────────────────────────────────────────────────────
if [[ "$SWAP" == "true" ]]; then
    SWAP_UNIT="$(systemd-escape --path "/dev/zvol/$RPOOL/swap").swap"
    systemctl enable "$SWAP_UNIT" 2>/dev/null || {
        echo "/dev/zvol/$RPOOL/swap  none  swap  defaults  0 0" >> /etc/fstab
    }
fi

bash /root/lib-chroot/password.sh

# Users are created by the Runner (lib/profiles.sh) after configure_system()
# returns — see ADRs 0001 and 0004.

bash /root/lib-chroot/extras.sh

echo ""
echo "[CHROOT] Configuration complete."
