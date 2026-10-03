#!/usr/bin/env bash
# =============================================================================
# lib/grub-common.sh — /etc/default/grub for a GRUB that reads /boot on ZFS
# =============================================================================
# Only tools/harden-boot.sh uses this now, to re-pin the default entry on an
# existing grub-mkconfig install. Fresh installs boot GRUB from the ESP with a
# rendered grub.cfg (lib/chroot/bootloader-grub.sh, ADR 0078). Defines a
# function only — no top-level side effects.
# =============================================================================

# Pure: emit /etc/default/grub content for a ZFS root. When <primary_vmlinuz> is
# non-empty it pins that kernel as the default top-level entry via
# GRUB_TOP_LEVEL — 10_linux moves it to the front of the sorted list — so a
# higher-versioned Stray Kernel cannot become the default boot entry (ADR 0038);
# the stray stays a selectable entry. An empty <primary_vmlinuz> omits the pin.
_grub_default_config() {
  # <extra_default> is appended to GRUB_CMDLINE_LINUX_DEFAULT (e.g. the zswap
  # fragment); empty leaves the default cmdline as just "quiet".
  local pool_root="$1" primary_vmlinuz="$2" extra_default="${3:-}"
  echo "GRUB_DEFAULT=0"
  [[ -n "$primary_vmlinuz" ]] && echo "GRUB_TOP_LEVEL=\"${primary_vmlinuz}\""
  cat << EOF
GRUB_TIMEOUT=4
GRUB_DISTRIBUTOR="Arch Linux (ZFS)"
GRUB_CMDLINE_LINUX_DEFAULT="quiet${extra_default:+ ${extra_default}}"
GRUB_CMDLINE_LINUX="root=ZFS=${pool_root} zfs_import_dir=/dev/disk/by-id"
GRUB_PRELOAD_MODULES="zfs"
GRUB_DISABLE_OS_PROBER=false
EOF
}
