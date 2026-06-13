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

# Pure: emit /etc/default/grub content for a ZFS root. When <primary_vmlinuz> is
# non-empty it pins that kernel as the default top-level entry via
# GRUB_TOP_LEVEL — 10_linux moves it to the front of the sorted list — so a
# higher-versioned Stray Kernel cannot become the default boot entry (ADR 0038);
# the stray stays a selectable entry. An empty <primary_vmlinuz> omits the pin.
_grub_default_config() {
  local pool_root="$1" primary_vmlinuz="$2"
  echo "GRUB_DEFAULT=0"
  [[ -n "$primary_vmlinuz" ]] && echo "GRUB_TOP_LEVEL=\"${primary_vmlinuz}\""
  cat << EOF
GRUB_TIMEOUT=4
GRUB_DISTRIBUTOR="Arch Linux (ZFS)"
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_CMDLINE_LINUX="root=ZFS=${pool_root} zfs_import_dir=/dev/disk/by-id"
GRUB_PRELOAD_MODULES="zfs"
GRUB_DISABLE_OS_PROBER=false
EOF
}

# Install grub + os-prober, write /etc/default/grub for a ZFS root, install the
# EFI binary, and regenerate grub.cfg. Inherits the caller's `set -Eeuo
# pipefail`. The root dataset is read from the live mount. Optional arg: the
# Primary Kernel package base (e.g. linux-lts) to pin as the default boot entry;
# omitted → no pin (preserves the previous highest-version-wins behavior).
grub_install_and_configure() {
  local primary_base="${1:-}"
  local pool_root primary_vmlinuz=""
  pool_root="$(findmnt -n -o SOURCE /)" # ZFS root dataset, e.g. rpool/ROOT/arch
  [[ -n "$pool_root" ]] || {
    echo "[grub-common] could not resolve ZFS root dataset for /" >&2
    return 1
  }
  [[ -n "$primary_base" ]] && primary_vmlinuz="/boot/vmlinuz-${primary_base}"

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

  _grub_default_config "$pool_root" "$primary_vmlinuz" > /etc/default/grub

  # ZPOOL_VDEV_NAME_PATH=YES lets grub-probe resolve ZFS-root vdevs by /dev path
  # so grub-mkconfig succeeds on ZFS without grub-libzfs (OpenZFS-documented).
  ZPOOL_VDEV_NAME_PATH=YES grub-mkconfig -o /boot/grub/grub.cfg
}
