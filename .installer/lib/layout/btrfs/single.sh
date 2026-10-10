#!/usr/bin/env bash
# =============================================================================
# lib/layout/btrfs/single.sh — btrfs Root Layout Adapter (single-disk, ADR 0043)
# =============================================================================
# A btrfs root over the shared non-ZFS root spine (lib/layout/nonzfs/root.sh):
# the spine owns the `ESP + [swap] + root` partitioning, optional LUKS, swap, and
# ESP mount; this adapter supplies the two leaf hooks (`root_adapter_mkfs`/`root_adapter_fstype`)
# and OVERRIDES `layout_create_pools` because a btrfs root is not a bare device —
# it carries a subvolume layout (@/@home/@log/@pkg/@snapshots, lib/layout/btrfs/
# subvol.sh) and boots a subvolume via `rootflags=subvol=@` (lib/layout/btrfs/
# boot.sh). Single-disk only this pass; native multi-disk raid lands in a later
# pass. Impermanence (the @blank rollback) is issue 08 — not here.
#
# HOOKS override the spine's: a plaintext single-disk btrfs needs no scan hook,
# but under impermanence (ADR 0044) the `btrfs-rollback` hook (+ the `btrfs` hook
# that supplies its binary) must precede `filesystems`, so this adapter publishes
# via `layout_btrfs_hooks` with the encryption + impermanence flags.
# =============================================================================

# shellcheck source=../nonzfs/root.sh
source "${BASH_SOURCE[0]%/*}/../nonzfs/root.sh"
# shellcheck source=./boot.sh
source "${BASH_SOURCE[0]%/*}/boot.sh"
# shellcheck source=./subvol.sh
source "${BASH_SOURCE[0]%/*}/subvol.sh"

# Publish HOOKS via layout_btrfs_hooks (not the spine's layout_nonzfs_hooks): single-disk, but
# carrying the encrypt hook when LUKS and the btrfs-rollback hook under
# impermanence. The root cmdline + fstab still come from layout_create_pools.
_layout_publish_boot() {
  local encryption="" impermanence=""
  [[ "$(layout_nonzfs_encryption_mode)" == "encrypted" ]] && encryption=encrypted
  [[ "$(install_config_impermanence_enabled)" == "true" ]] && impermanence=impermanence
  # shellcheck disable=SC2034 # consumed by install_state_write
  LAYOUT_HOOKS="$(layout_btrfs_hooks "$encryption" "" "$impermanence")"
}

# Format the root device btrfs. -f: overwrite an existing signature (the spine
# already wiped + repartitioned).
root_adapter_mkfs() { mkfs.btrfs -f "$1"; }

# The log label + the fstab fs-type (subvol fstab lines hard-code btrfs anyway).
root_adapter_fstype() { echo btrfs; }

# Override the spine's create verb: format btrfs, lay out the subvolumes, mount @
# as the root with the nested subvols underneath, then publish the subvol-aware
# root cmdline (rootflags=subvol=@) + the per-subvol fstab and the swap tail. The
# swap tail + crypttab reuse the spine's shared `layout_nonzfs_swap_tail`.
layout_create_pools() {
  layout_enter_phase pools
  section "Formatting btrfs Root + Subvolumes"
  root_adapter_mkfs "$_LAYOUT_IMPL_ROOT_DEV"
  # btrfs is a kernel module (not built-in) — load it before mounting the fresh
  # fs on the live ISO (same hazard the ext4 spine modprobes for).
  modprobe btrfs 2>/dev/null || true
  # Lay out @/@home/@log/@pkg/@snapshots + mount @ as root (shared with multi).
  layout_btrfs_create_and_mount_subvolumes "$_LAYOUT_IMPL_ROOT_DEV"

  # Resolve the root= UUID + the fstab mount source. Encrypted: the cmdline boots
  # the LUKS container UUID (opened as cryptroot), fstab references the mapper.
  # Plaintext: both use the btrfs filesystem UUID (shared by every subvol).
  local encryption encflag="" uuid source_device
  encryption="$(layout_nonzfs_encryption_mode)"
  if [[ "$encryption" == "encrypted" ]]; then
    encflag=encrypted
    uuid="$_LAYOUT_IMPL_LUKS_ROOT_UUID"
    source_device="/dev/mapper/cryptroot"
  else
    uuid="$(blkid -s UUID -o value "$_LAYOUT_IMPL_ROOT_DEV")"
    source_device="UUID=${uuid}"
  fi
  # shellcheck disable=SC2034 # consumed by install_state_write
  LAYOUT_ROOT_CMDLINE="$(layout_btrfs_root_cmdline "$uuid" @ "$encflag")"

  # fstab: the subvol block + the shared swap tail (also sets LAYOUT_CRYPTTAB).
  layout_nonzfs_swap_tail "$encryption"
  # shellcheck disable=SC2034 # consumed by chroot_write_fstab
  LAYOUT_FSTAB_EXTRA="$(layout_btrfs_root_fstab "$source_device")${_NZROOT_SWAP_FSTAB}"
  info "btrfs root + subvolumes formatted, mounted at $MOUNT_ROOT"
  layout_exit_phase pools
}
