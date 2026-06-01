#!/usr/bin/env bash
# =============================================================================
# lib/grub-common.sh — shared GRUB installer (single source of truth)
# =============================================================================
# Sourced inside arch-chroot by BOTH grub entry points:
#   - lib/chroot/bootloader-grub.sh   (adapter, when options.bootloader=grub)
#   - programs/bootloader/grub/install.sh   (system-program, declarative path)
#
# Staged into both runtime trees (/root/lib-chroot and /var/tmp/.os-runtime/lib)
# so each entry point is self-contained. Defines a function only — no top-level
# side effects — and logs via plain echo (the adapter has no Shell Stdlib).
# =============================================================================

# Install grub + os-prober, write /etc/default/grub for a ZFS root, install the
# EFI binary, and regenerate grub.cfg. Inherits the caller's `set -Eeuo
# pipefail`. The root dataset is read from the live mount so neither caller
# needs install-state.
grub_install_and_configure() {
  local pool_root
  pool_root="$(findmnt -n -o SOURCE /)" # ZFS root dataset, e.g. rpool/ROOT/arch
  [[ -n "$pool_root" ]] || {
    echo "[grub-common] could not resolve ZFS root dataset for /" >&2
    return 1
  }

  # paru is unavailable during the chroot phase — use pacman. --needed makes
  # this a no-op when bootloader=grub already pacstrapped grub.
  pacman -S --noconfirm --needed grub os-prober

  # GRUB reads ZFS pools natively — kernel/initramfs stay on the ZFS dataset.
  # --removable also writes the EFI/BOOT/BOOTX64.EFI fallback path, which laptop
  # firmware that forgets NVRAM entries will still boot.
  grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=GRUB \
    --recheck \
    --removable

  cat > /etc/default/grub << EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=4
GRUB_DISTRIBUTOR="Arch Linux (ZFS)"
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_CMDLINE_LINUX="root=ZFS=${pool_root} zfs_import_dir=/dev/disk/by-id"
GRUB_PRELOAD_MODULES="zfs"
GRUB_DISABLE_OS_PROBER=false
EOF

  # ZPOOL_VDEV_NAME_PATH=YES lets grub-probe resolve ZFS-root vdevs by /dev path
  # so grub-mkconfig succeeds on ZFS without grub-libzfs (OpenZFS-documented).
  ZPOOL_VDEV_NAME_PATH=YES grub-mkconfig -o /boot/grub/grub.cfg
}
