#!/usr/bin/env bash
# =============================================================================
# lib/layout/btrfs/single.sh — btrfs Root Layout Adapter (single-disk, ADR 0043)
# =============================================================================
# A btrfs root over the shared non-ZFS root spine (lib/layout/nonzfs/root.sh):
# the spine owns the `ESP + [swap] + root` partitioning, optional LUKS, swap, and
# ESP mount; this adapter supplies the two leaf hooks (`_root_mkfs`/`_root_fstype`)
# and OVERRIDES `layout_create_pools` because a btrfs root is not a bare device —
# it carries a subvolume layout (@/@home/@log/@pkg/@snapshots, lib/layout/btrfs/
# subvol.sh) and boots a subvolume via `rootflags=subvol=@` (lib/layout/btrfs/
# boot.sh). Single-disk only this pass; native multi-disk raid lands in a later
# pass. Impermanence (the @blank rollback) is issue 08 — not here.
#
# HOOKS override the spine's: a plaintext single-disk btrfs needs no scan hook,
# but under impermanence (ADR 0044) the `btrfs-rollback` hook (+ the `btrfs` hook
# that supplies its binary) must precede `filesystems`, so this adapter publishes
# via `btrfs_hooks` with the encryption + impermanence flags.
# =============================================================================

# shellcheck source=../nonzfs/root.sh
source "${BASH_SOURCE[0]%/*}/../nonzfs/root.sh"
# shellcheck source=./boot.sh
source "${BASH_SOURCE[0]%/*}/boot.sh"
# shellcheck source=./subvol.sh
source "${BASH_SOURCE[0]%/*}/subvol.sh"

# Publish HOOKS via btrfs_hooks (not the spine's nonzfs_hooks): single-disk, but
# carrying the encrypt hook when LUKS and the btrfs-rollback hook under
# impermanence. The root cmdline + fstab still come from layout_create_pools.
_layout_publish_boot() {
  local enc="" imp=""
  [[ "$(_nzroot_enc_mode)" == "encrypted" ]] && enc=encrypted
  [[ "$(install_config_impermanence_enabled)" == "true" ]] && imp=impermanence
  # shellcheck disable=SC2034 # consumed by install_state_write
  LAYOUT_HOOKS="$(btrfs_hooks "$enc" "" "$imp")"
}

# Format the root device btrfs. -f: overwrite an existing signature (the spine
# already wiped + repartitioned).
_root_mkfs() { mkfs.btrfs -f "$1"; }

# The log label + the fstab fs-type (subvol fstab lines hard-code btrfs anyway).
_root_fstype() { echo btrfs; }

# Override the spine's create verb: format btrfs, lay out the subvolumes, mount @
# as the root with the nested subvols underneath, then publish the subvol-aware
# root cmdline (rootflags=subvol=@) + the per-subvol fstab and the swap tail. The
# swap tail + crypttab reuse the spine's shared `_nzroot_swap_tail`.
layout_create_pools() {
  _layout_enter_phase pools
  section "Formatting btrfs Root + Subvolumes"
  _root_mkfs "$_LAYOUT_IMPL_ROOT_DEV"
  # btrfs is a kernel module (not built-in) — load it before mounting the fresh
  # fs on the live ISO (same hazard the ext4 spine modprobes for).
  modprobe btrfs 2>/dev/null || true
  # Lay out @/@home/@log/@pkg/@snapshots + mount @ as root (shared with multi).
  _btrfs_create_and_mount_subvols "$_LAYOUT_IMPL_ROOT_DEV"

  # Resolve the root= UUID + the fstab mount source. Encrypted: the cmdline boots
  # the LUKS container UUID (opened as cryptroot), fstab references the mapper.
  # Plaintext: both use the btrfs filesystem UUID (shared by every subvol).
  local enc encflag="" uuid src
  enc="$(_nzroot_enc_mode)"
  if [[ "$enc" == "encrypted" ]]; then
    encflag=encrypted
    uuid="$_LAYOUT_IMPL_LUKS_ROOT_UUID"
    src="/dev/mapper/cryptroot"
  else
    uuid="$(blkid -s UUID -o value "$_LAYOUT_IMPL_ROOT_DEV")"
    src="UUID=${uuid}"
  fi
  # shellcheck disable=SC2034 # consumed by install_state_write
  LAYOUT_ROOT_CMDLINE="$(btrfs_root_cmdline "$uuid" @ "$encflag")"

  # fstab: the subvol block + the shared swap tail (also sets LAYOUT_CRYPTTAB).
  _nzroot_swap_tail "$enc"
  # shellcheck disable=SC2034 # consumed by write_fstab
  LAYOUT_FSTAB_EXTRA="$(btrfs_root_fstab "$src")${_NZROOT_SWAP_FSTAB}"
  info "btrfs root + subvolumes formatted, mounted at $MOUNT_ROOT"
  _layout_exit_phase pools
}
