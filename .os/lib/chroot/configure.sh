#!/usr/bin/env bash
# lib/chroot/configure.sh — Chroot Configuration Module: orchestrator
# Entry point run by configure_system() via:
#   ROOT_PW="<pw>" arch-chroot /mnt bash /root/lib-chroot/configure.sh
#
# All non-secret params come from install-state.json
# (written before arch-chroot).
# ROOT_PW is passed as an env var — never written to disk.
set -Eeuo pipefail
trap 'echo "[chroot:configure] failed at line $LINENO" >&2' ERR

# shellcheck source=./install-state.sh
STATE="${STATE:-/root/lib-chroot/install-state.json}"
_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
_INSTALL_STATE_SH="$_LIB_DIR/install-state.sh"
[[ -f "$_INSTALL_STATE_SH" ]] || _INSTALL_STATE_SH="$_LIB_DIR/../install-state.sh"
# shellcheck disable=SC1090
source "$_INSTALL_STATE_SH"
install_state_load "$STATE"

# shellcheck source=./base-services.sh
source "$_LIB_DIR/base-services.sh"

# shellcheck source=./udisks.sh
source "$_LIB_DIR/udisks.sh"

# shellcheck source=./zfs-import.sh
source "$_LIB_DIR/zfs-import.sh"

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

# ── Network, time & cron services ─────────────────────────────────────────────
# Always-on base daemons (incl. cronie, ADR 0026) — see base-services.sh.
enable_base_services

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

# ── udisks: hide ZFS pool members from file managers ──────────────────────────
# Without this a udisks2-backed file manager lists ZFS members as removable
# drives, prompts for a password, then fails to mount (ADR 0031). Written
# unconditionally — a harmless no-op when udisks2 isn't installed (servers).
udisks_write_zfs_ignore_rule

# ── ZFS services ─────────────────────────────────────────────────────────────
# Import order: zfs-import-cache (fast) → zfs-import-scan (fallback)
#   → zfs-import.target → zfs-mount → zfs-zed → zfs.target
systemctl enable zfs-import-cache
systemctl enable zfs-import-scan
systemctl enable zfs-import.target
systemctl enable zfs-mount
systemctl enable zfs-zed
systemctl enable zfs.target

# Decouple the post-boot import services from the deprecated
# systemd-udev-settle so a slow/stalled settle can't fail pool imports or
# stall boot. Ships full /etc replacement units (a reset drop-in does not
# remove the dep on systemd 260). The initramfs stays the authoritative
# importer (ADR 0030).
zfs_import_write_settle_overrides ""

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

# Users are created by the Runner (lib/profiles/runner.sh) after configure_system()
# returns — see ADRs 0001 and 0004.

bash /root/lib-chroot/extras.sh

# Impermanence is intentionally NOT invoked here — it moves /root into the
# persist dataset, which would erase /root/lib-chroot/ before the Profiles
# Runner can use it. apply_impermanence() runs it from the host after
# run_profiles. See ADRs 0001 and 0004.

echo ""
echo "[CHROOT] Configuration complete."
