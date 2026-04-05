#!/usr/bin/env bash
# =============================================================================
# lib/chroot.sh — System configuration inside arch-chroot
# =============================================================================
# Sourced by 03-install.sh.
# Requires: lib/common.sh already sourced.
#
# Provides:
#   write_fstab_single    — writes /etc/fstab for single-disk layout
#   write_fstab_multi     — writes /etc/fstab for multi-disk layout
#   write_esp_mirror_hook — installs a pacman hook that syncs secondary ESPs
#   configure_system      — seeds ZFS state, then runs the full chroot configuration
#
# The configure_system function passes all needed values into arch-chroot as
# positional arguments to avoid relying on exported environment variables,
# which are not reliably inherited across arch-chroot boundaries.
# =============================================================================

# =============================================================================
# FSTAB WRITERS
# =============================================================================

write_fstab_single() {
    # Single-disk fstab: one ESP entry only.
    # ZFS datasets are auto-mounted by zfs-mount-generator (no fstab entries).
    {
        echo "# EFI System Partition"
        echo "UUID=$(blkid -s UUID -o value "$SINGLE_ESP_PART")  /boot/efi  vfat  umask=0077  0 2"
        echo ""
        echo "# ZFS datasets are auto-mounted by zfs-mount-generator"
        echo "# (reads /etc/zfs/zfs-list.cache/<poolname> at boot)"
    } > "${MOUNT_ROOT}/etc/fstab"
    info "fstab written (single-disk)."
}

write_fstab_multi() {
    # Multi-disk fstab: primary ESP + all secondary ESPs.
    # Secondary ESPs are kept in sync by the 95-esp-mirror pacman hook.
    {
        echo "# EFI System Partition — primary ($(basename "${OS_ESP_PARTS[0]}"))"
        echo "UUID=$(blkid -s UUID -o value "${OS_ESP_PARTS[0]}")  /boot/efi  vfat  umask=0077  0 2"

        for i in $(seq 1 $(( ${#OS_ESP_PARTS[@]} - 1 ))); do
            echo ""
            echo "# EFI System Partition — secondary ${i} (kept in sync by pacman hook)"
            echo "UUID=$(blkid -s UUID -o value "${OS_ESP_PARTS[$i]}")  /boot/efi${i}  vfat  umask=0077  0 2"
        done

        echo ""
        echo "# ZFS datasets are auto-mounted by zfs-mount-generator"
    } > "${MOUNT_ROOT}/etc/fstab"
    info "fstab written (multi-disk, ${#OS_ESP_PARTS[@]} ESP(s))."
}

# =============================================================================
# ESP MIRROR PACMAN HOOK
# =============================================================================

write_esp_mirror_hook() {
    # Installs a pacman hook that rsyncs the primary ESP (/boot/efi) to all
    # secondary ESPs (/boot/efi1, /boot/efi2, ...) after every kernel update
    # or systemd-boot update. This keeps every OS disk independently bootable.
    #
    # The hook fires on any change to:
    #   usr/lib/modules/*/vmlinuz  — kernel image updated
    #   usr/lib/systemd/boot/efi/*.efi  — systemd-boot EFI binary updated

    local esp_count="$1"
    (( esp_count > 1 )) || return   # nothing to mirror for single-ESP installs

    mkdir -p "${MOUNT_ROOT}/etc/pacman.d/hooks"
    cat > "${MOUNT_ROOT}/etc/pacman.d/hooks/95-esp-mirror.hook" << 'HOOK'
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/lib/modules/*/vmlinuz
Target = usr/lib/systemd/boot/efi/*.efi

[Action]
Description = Mirroring ESP to secondary OS disks...
When = PostTransaction
Exec = /usr/bin/bash -c 'for d in /boot/efi*/; do [[ "$d" != "/boot/efi/" ]] && rsync -a --delete /boot/efi/ "$d"; done'
HOOK
    info "ESP mirror pacman hook installed."
}

# =============================================================================
# CHROOT CONFIGURATION
# =============================================================================

configure_system() {
    section "Configuring System (arch-chroot)"

    # ── Seed ZFS state into the new root ──────────────────────────────────────
    # The pool cache and hostid must exist in the new system before the
    # initramfs is built, otherwise the ZFS hook cannot import the pool at boot.
    mkdir -p "${MOUNT_ROOT}/etc/zfs"
    cp /etc/zfs/zpool.cache "${MOUNT_ROOT}/etc/zfs/" 2>/dev/null \
        || warn "zpool.cache not found — pool may not import on first boot without zfs-import-scan."
    cp /etc/hostid "${MOUNT_ROOT}/etc/hostid"

    # Copy archzfs repo config so the new system can update ZFS packages
    cp /etc/pacman.conf "${MOUNT_ROOT}/etc/pacman.conf"

    # ── Copy extras/ scripts for execution inside chroot ──────────────────────
    if [[ -d "${SCRIPT_DIR}/extras" ]]; then
        cp -r "${SCRIPT_DIR}/extras" "${MOUNT_ROOT}/root/extras"
        chmod +x "${MOUNT_ROOT}/root/extras/"*.sh 2>/dev/null || true
        info "Copied extras/ → /root/extras/"
    else
        warn "extras/ directory not found at ${SCRIPT_DIR}/extras — post-install scripts won't run."
    fi

    # ── Gather all values to pass into chroot ─────────────────────────────────
    local hostname username locale timezone keymap
    local rpool swap esp_count
    local do_kde do_backup do_security

    hostname="$(cfg '.system.hostname')"
    username="$(cfg '.system.username')"
    locale="$(cfg   '.system.locale')"
    timezone="$(cfg '.system.timezone')"
    keymap="$(cfgo  '.system.keymap')";  keymap="${keymap:-us}"
    swap="$(cfgo    '.options.swap')";   swap="${swap:-true}"

    do_kde="$(cfgo      '.post_install.kde')";      do_kde="${do_kde:-false}"
    do_backup="$(cfgo   '.post_install.backup')";   do_backup="${do_backup:-false}"
    do_security="$(cfgo '.post_install.security')"; do_security="${do_security:-false}"

    if [[ "$INSTALL_MODE" == "single" ]]; then
        rpool="$(cfgo '.os_pool_name')"; rpool="${rpool:-rpool}"
        esp_count=1
        write_fstab_single
    else
        rpool="$(cfg '.os_pool.pool_name')"
        esp_count="${#OS_ESP_PARTS[@]}"
        write_fstab_multi
        write_esp_mirror_hook "$esp_count"
    fi

    # ── Run configuration inside chroot ───────────────────────────────────────
    # Values are passed as positional args ($1–$11) to avoid export issues.
    # The heredoc is quoted ('CHROOT') so variable expansion happens INSIDE
    # the chroot shell, not in the outer script.

    arch-chroot "${MOUNT_ROOT}" /bin/bash -s \
        "$hostname"   "$timezone"  "$locale"     "$keymap" \
        "$username"   "$rpool"     "$swap"        "$esp_count" \
        "$do_kde"     "$do_backup" "$do_security" \
        << 'CHROOT'

# ── Positional argument unpacking ────────────────────────────────────────────
HOSTNAME="$1";   TIMEZONE="$2";   LOCALE="$3";    KEYMAP="$4"
USERNAME="$5";   RPOOL="$6";      SWAP="$7";      ESP_COUNT="$8"
DO_KDE="$9";     DO_BACKUP="${10}"; DO_SECURITY="${11}"

set -e

# ── Timezone ─────────────────────────────────────────────────────────────────
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
echo "Timezone set: $TIMEZONE"

# ── Locale ───────────────────────────────────────────────────────────────────
# Uncomment the locale in locale.gen if it exists commented, else append it
if grep -q "^#${LOCALE} UTF-8" /etc/locale.gen; then
    sed -i "s/^#${LOCALE} UTF-8/${LOCALE} UTF-8/" /etc/locale.gen
else
    echo "${LOCALE} UTF-8" >> /etc/locale.gen
fi
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# ── Hostname & /etc/hosts ─────────────────────────────────────────────────────
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# ── mkinitcpio — ZFS hook ─────────────────────────────────────────────────────
# The ZFS hook (from zfs-dkms/zfs-utils) imports pools early in the initramfs.
# It must appear after 'block' (so block devices are visible) and before
# 'filesystems' (so ZFS datasets are mounted before pivot_root).
#
# Hook name detection: mkinitcpio >= 0.16 (Arch 2023+) renamed 'modconf'→'kmod'.
# Check for the hook file directly — more reliable than --listhooks.
if [[ -e /usr/lib/initcpio/hooks/kmod ]]; then
    MODCONF_HOOK="kmod"
else
    MODCONF_HOOK="modconf"
fi
sed -i "s/^HOOKS=.*/HOOKS=(base udev autodetect ${MODCONF_HOOK} block keyboard zfs filesystems)/" \
    /etc/mkinitcpio.conf
mkinitcpio -P

# ── systemd-boot ─────────────────────────────────────────────────────────────
# Install systemd-boot EFI binaries to /boot/efi/EFI/systemd/
bootctl --esp-path=/boot/efi install

POOL_ROOT="$RPOOL/ROOT/arch"
mkdir -p /boot/efi/loader/entries

# Bootloader configuration
cat > /boot/efi/loader/loader.conf << EOF
default arch-zfs.conf
timeout 4
console-mode max
editor no
EOF

# Normal boot entry
cat > /boot/efi/loader/entries/arch-zfs.conf << EOF
title   Arch Linux (ZFS)
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options root=ZFS=$POOL_ROOT rw
EOF

# Fallback entry (verbose initramfs, used for troubleshooting)
cat > /boot/efi/loader/entries/arch-zfs-fallback.conf << EOF
title   Arch Linux (ZFS — fallback)
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /amd-ucode.img
initrd  /initramfs-linux-fallback.img
options root=ZFS=$POOL_ROOT rw
EOF

# Copy kernel and initramfs into the ESP.
# systemd-boot reads them directly from the ESP — they must be there, not
# just in /boot, because the ESP is what the firmware can access before the
# ZFS root is mounted.
cp /boot/vmlinuz-linux                /boot/efi/
cp /boot/initramfs-linux.img          /boot/efi/
cp /boot/initramfs-linux-fallback.img /boot/efi/
[[ -f /boot/intel-ucode.img ]] && cp /boot/intel-ucode.img /boot/efi/ || true
[[ -f /boot/amd-ucode.img   ]] && cp /boot/amd-ucode.img   /boot/efi/ || true

# ── Secondary ESP mirroring ───────────────────────────────────────────────────
# For multi-disk installs: rsync the primary ESP to each secondary, then
# register each secondary as an independent UEFI boot entry via efibootmgr.
# This allows booting from any OS disk if the primary fails.
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
                --loader '\EFI\systemd\systemd-bootx64.efi' \
                || true   # non-fatal: UEFI vars may be read-only in some VMs
        fi
    done
fi

# ── Network & time services ───────────────────────────────────────────────────
# NetworkManager handles wired and wireless connections.
systemctl enable NetworkManager

# systemd-resolved provides a caching stub DNS resolver.
# /etc/resolv.conf must point to its stub socket for DNS to work after boot.
systemctl enable systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# systemd-timesyncd is a lightweight NTP client. It syncs the clock at boot
# using the servers in /etc/systemd/timesyncd.conf (defaults to the pool.ntp.org pool).
systemctl enable systemd-timesyncd

# ── ZFS services ─────────────────────────────────────────────────────────────
# Boot sequence:
#   1. zfs-import-cache  — reads /etc/zfs/zpool.cache and imports listed pools
#   2. zfs-import.target — signals all imports done; other units wait on this
#   3. zfs-mount         — mounts all ZFS datasets with canmount!=off
#   4. zfs-zed           — ZFS Event Daemon: handles scrub alerts, fault events
#   5. zfs.target        — passive aggregation target that downstream units want
systemctl enable zfs-import-cache
systemctl enable zfs-import.target
systemctl enable zfs-mount
systemctl enable zfs-zed
systemctl enable zfs.target

# Populate the zfs-mount-generator dataset cache.
# The generator (/usr/lib/systemd/system-generators/zfs-mount-generator) reads
# /etc/zfs/zfs-list.cache/<poolname> at boot to know which datasets to mount.
# It does not need to be "enabled" — generators always run at boot.
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
    # systemd-escape --path converts /dev/zvol/rpool/swap → dev-zvol-rpool-swap
    # The .swap unit name is that escaped path + ".swap"
    SWAP_UNIT="$(systemd-escape --path "/dev/zvol/$RPOOL/swap").swap"
    systemctl enable "$SWAP_UNIT" 2>/dev/null || {
        # Fallback: add to fstab — systemd reads fstab at boot as an alternative
        echo "/dev/zvol/$RPOOL/swap  none  swap  defaults  0 0" >> /etc/fstab
    }
fi

# ── Passwords & user ─────────────────────────────────────────────────────────
# NOTE on ZFS encryption:
#   If encryption was enabled, the ZFS passphrase is prompted at boot by the
#   initramfs ZFS hook (zfs-load-key). No PAM module is needed for this — it
#   happens before any user login.
#   To switch to a keyfile for unattended boots:
#     zfs change-key -o keyformat=raw -o keylocation=file:///etc/zfs/<key> <dataset>

echo "--- Set ROOT password ---"
passwd root

useradd -m -G wheel,audio,video,storage,optical,network -s /bin/bash "$USERNAME"
echo "--- Set password for $USERNAME ---"
passwd "$USERNAME"

# Enable sudo for wheel group (uncomments the relevant line in /etc/sudoers)
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# ── Post-install optional scripts ─────────────────────────────────────────────
# Each script runs inside this chroot and has full access to the new system.
# They are copied from extras/ on the installer USB by configure_system().
[[ "$DO_KDE"      == "true" && -f /root/extras/kde.sh      ]] && bash /root/extras/kde.sh
[[ "$DO_BACKUP"   == "true" && -f /root/extras/backup.sh   ]] && bash /root/extras/backup.sh
[[ "$DO_SECURITY" == "true" && -f /root/extras/security.sh ]] && bash /root/extras/security.sh

echo ""
echo "[CHROOT] Configuration complete."
CHROOT
}
