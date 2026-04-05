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
  } >"${MOUNT_ROOT}/etc/fstab"
  info "fstab written (single-disk)."
}

write_fstab_multi() {
  # Multi-disk fstab: primary ESP + all secondary ESPs.
  # Secondary ESPs are kept in sync by the 95-esp-mirror pacman hook.
  {
    echo "# EFI System Partition — primary ($(basename "${OS_ESP_PARTS[0]}"))"
    echo "UUID=$(blkid -s UUID -o value "${OS_ESP_PARTS[0]}")  /boot/efi  vfat  umask=0077  0 2"

    for i in $(seq 1 $((${#OS_ESP_PARTS[@]} - 1))); do
      echo ""
      echo "# EFI System Partition — secondary ${i} (kept in sync by pacman hook)"
      echo "UUID=$(blkid -s UUID -o value "${OS_ESP_PARTS[$i]}")  /boot/efi${i}  vfat  umask=0077  0 2"
    done

    echo ""
    echo "# ZFS datasets are auto-mounted by zfs-mount-generator"
  } >"${MOUNT_ROOT}/etc/fstab"
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
  ((esp_count > 1)) || return # nothing to mirror for single-ESP installs

  mkdir -p "${MOUNT_ROOT}/etc/pacman.d/hooks"
  cat >"${MOUNT_ROOT}/etc/pacman.d/hooks/95-esp-mirror.hook" <<'HOOK'
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
  cp /etc/zfs/zpool.cache "${MOUNT_ROOT}/etc/zfs/" 2>/dev/null ||
    warn "zpool.cache not found — pool may not import on first boot without zfs-import-scan."
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
  locale="$(cfg '.system.locale')"
  timezone="$(cfg '.system.timezone')"
  keymap="$(cfgo '.system.keymap')"
  keymap="${keymap:-us}"
  swap="$(cfgo '.options.swap')"
  swap="${swap:-true}"

  do_kde="$(cfgo '.post_install.kde')"
  do_kde="${do_kde:-false}"
  do_backup="$(cfgo '.post_install.backup')"
  do_backup="${do_backup:-false}"
  do_security="$(cfgo '.post_install.security')"
  do_security="${do_security:-false}"

  if [[ "$INSTALL_MODE" == "single" ]]; then
    rpool="$(cfgo '.os_pool_name')"
    rpool="${rpool:-rpool}"
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

  # Kernel and bootloader selection from config
  local kernel
  kernel="$(cfgo '.options.kernel')"
  kernel="${kernel:-lts}"
  local bootloader
  bootloader="$(cfgo '.options.bootloader')"
  bootloader="${bootloader:-systemd-boot}"

  arch-chroot "${MOUNT_ROOT}" /bin/bash -s \
    "$hostname" "$timezone" "$locale" "$keymap" \
    "$username" "$rpool" "$swap" "$esp_count" \
    "$do_kde" "$do_backup" "$do_security" \
    "$kernel" "$bootloader" \
    <<'CHROOT'

# ── Positional argument unpacking ────────────────────────────────────────────
HOSTNAME="$1";   TIMEZONE="$2";   LOCALE="$3";    KEYMAP="$4"
USERNAME="$5";   RPOOL="$6";      SWAP="$7";      ESP_COUNT="$8"
DO_KDE="$9";     DO_BACKUP="${10}"; DO_SECURITY="${11}"
KERNEL="${12:-lts}"; BOOTLOADER="${13:-systemd-boot}"

# Derive kernel image names from the kernel flavour.
# linux-lts images have '-lts' in the filename; linux (default) do not.
if [[ "$KERNEL" == "lts" ]]; then
    VMLINUZ="vmlinuz-linux-lts"
    INITRAMFS="initramfs-linux-lts.img"
    INITRAMFS_FB="initramfs-linux-lts-fallback.img"
else
    VMLINUZ="vmlinuz-linux"
    INITRAMFS="initramfs-linux.img"
    INITRAMFS_FB="initramfs-linux-fallback.img"
fi

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

# Determine the preset file name from the kernel flavour.
# linux-lts  → /etc/mkinitcpio.d/linux-lts.preset
# linux       → /etc/mkinitcpio.d/linux.preset
if [[ "$KERNEL" == "lts" ]]; then
    PRESET_NAME="linux-lts"
else
    PRESET_NAME="linux"
fi
PRESET_FILE="/etc/mkinitcpio.d/${PRESET_NAME}.preset"

# Ensure the preset includes a 'fallback' entry.
# On minimal installs the preset may only have 'default'.
if [[ -f "$PRESET_FILE" ]]; then
    if ! grep -q "^PRESETS=.*fallback" "$PRESET_FILE"; then
        echo "Adding fallback preset to ${PRESET_FILE} ..."
        sed -i "s/^PRESETS=('default')/PRESETS=('default' 'fallback')/" "$PRESET_FILE"
        cat >> "$PRESET_FILE" << PRESET

# Fallback preset — builds without autodetect (all modules included)
# Added by the ZFS installer to ensure a recovery boot option exists.
fallback_config="/etc/mkinitcpio.conf"
fallback_image="/boot/${INITRAMFS_FB}"
fallback_options="-S autodetect"
PRESET
    fi
else
    echo "Warning: preset file not found at ${PRESET_FILE} — mkinitcpio -P will use defaults."
fi

mkinitcpio -P

# ── Bootloader installation ───────────────────────────────────────────────────
POOL_ROOT="$RPOOL/ROOT/arch"

if [[ "$BOOTLOADER" == "grub" ]]; then

    # ── GRUB ─────────────────────────────────────────────────────────────────
    # GRUB can read ZFS pools natively and does not need kernel/initramfs
    # copied to the ESP — it reads them directly from the ZFS dataset.
    # grub-install writes the EFI binary; grub-mkconfig generates grub.cfg.

    # Install GRUB EFI binary to the ESP
    grub-install \
        --target=x86_64-efi \
        --efi-directory=/boot/efi \
        --bootloader-id=GRUB \
        --recheck

    # Tell GRUB which ZFS dataset is the root filesystem
    # GRUB_CMDLINE_LINUX sets the kernel command line for all entries
    cat > /etc/default/grub << EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=4
GRUB_DISTRIBUTOR="Arch Linux (ZFS)"
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_CMDLINE_LINUX="root=ZFS=${POOL_ROOT}"
GRUB_PRELOAD_MODULES="zfs"
GRUB_DISABLE_OS_PROBER=false
EOF

    # Generate GRUB configuration — discovers all installed kernels automatically
    grub-mkconfig -o /boot/grub/grub.cfg

    echo "GRUB installed. Boot entries generated by grub-mkconfig."

else

    # ── systemd-boot (default) ────────────────────────────────────────────────
    # systemd-boot is a lightweight EFI loader. It cannot read ZFS, so kernel
    # and initramfs must be copied into the FAT32 ESP where firmware can reach them.
    # A pacman hook (95-esp-sync.hook, installed below) keeps them in sync on updates.

    bootctl --esp-path=/boot/efi install

    mkdir -p /boot/efi/loader/entries

    cat > /boot/efi/loader/loader.conf << EOF
default arch-zfs.conf
timeout 4
console-mode max
editor no
EOF

    # Normal boot entry
    cat > /boot/efi/loader/entries/arch-zfs.conf << EOF
title   Arch Linux (ZFS${KERNEL:+ — ${KERNEL}-lts})
linux   /${VMLINUZ}
initrd  /intel-ucode.img
initrd  /amd-ucode.img
initrd  /${INITRAMFS}
options root=ZFS=${POOL_ROOT} rw
EOF

    # Fallback entry — uses a verbose initramfs for troubleshooting boot failures
    cat > /boot/efi/loader/entries/arch-zfs-fallback.conf << EOF
title   Arch Linux (ZFS — fallback)
linux   /${VMLINUZ}
initrd  /intel-ucode.img
initrd  /amd-ucode.img
initrd  /${INITRAMFS_FB}
options root=ZFS=${POOL_ROOT} rw
EOF

    # Copy kernel and initramfs to the ESP.
    # systemd-boot reads these directly from the FAT32 ESP — the ZFS root
    # is not yet mounted at the point the firmware loads them.
    cp "/boot/${VMLINUZ}"   /boot/efi/
    cp "/boot/${INITRAMFS}" /boot/efi/

    # The fallback initramfs may not exist if the linux-lts preset only defines
    # the default image. Generate it explicitly if missing, then copy if present.
    if [[ ! -f "/boot/${INITRAMFS_FB}" ]]; then
        echo "Fallback initramfs not found — generating now ..."
        mkinitcpio -p "linux-${KERNEL/default/}" -S autodetect 2>/dev/null \
            || mkinitcpio -g "/boot/${INITRAMFS_FB}" 2>/dev/null \
            || true
    fi
    if [[ -f "/boot/${INITRAMFS_FB}" ]]; then
        cp "/boot/${INITRAMFS_FB}" /boot/efi/
    else
        # No fallback available — remove the fallback boot entry so systemd-boot
        # does not show a broken entry that points to a missing file.
        rm -f /boot/efi/loader/entries/arch-zfs-fallback.conf
        echo "Note: fallback initramfs not available — fallback boot entry removed."
    fi

    [[ -f /boot/intel-ucode.img ]] && cp /boot/intel-ucode.img /boot/efi/ || true
    [[ -f /boot/amd-ucode.img   ]] && cp /boot/amd-ucode.img   /boot/efi/ || true

    # Install a pacman hook so the ESP copies are updated on every kernel upgrade.
    # Without this, the files in the ESP would go stale after the first update.
    mkdir -p /etc/pacman.d/hooks
    cat > /etc/pacman.d/hooks/96-esp-kernel-sync.hook << 'HOOK'
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/lib/modules/*/vmlinuz

[Action]
Description = Syncing kernel and initramfs to ESP...
When = PostTransaction
Exec = /usr/bin/bash -c '\
    for f in /boot/vmlinuz-linux* /boot/initramfs-linux*.img \
              /boot/intel-ucode.img /boot/amd-ucode.img; do \
        [[ -f "$f" ]] && cp "$f" /boot/efi/ && \
            for d in /boot/efi*/; do \
                [[ "$d" != "/boot/efi/" ]] && cp "$f" "$d"; \
            done; \
    done'
HOOK

    echo "systemd-boot installed."

fi

# ── Secondary ESP mirroring ───────────────────────────────────────────────────
# For multi-disk installs: rsync the primary ESP to each secondary, then
# register each secondary as an independent UEFI boot entry via efibootmgr.
# This allows booting from any OS disk if the primary fails.
# GRUB: the EFI binary is at EFI/GRUB/grubx64.efi
# systemd-boot: the EFI binary is at EFI/systemd/systemd-bootx64.efi
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
