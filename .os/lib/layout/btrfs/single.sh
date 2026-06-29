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
# HOOKS are unchanged from the spine (single-disk btrfs needs no btrfs scan hook
# and no rollback hook yet), so `_layout_publish_boot` is reused as-is.
# =============================================================================

# shellcheck source=../nonzfs/root.sh
source "${BASH_SOURCE[0]%/*}/../nonzfs/root.sh"
# shellcheck source=./boot.sh
source "${BASH_SOURCE[0]%/*}/boot.sh"
# shellcheck source=./subvol.sh
source "${BASH_SOURCE[0]%/*}/subvol.sh"

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

  # Create the subvolumes on the top-level (subvolid=5), then remount @ as root
  # with the nested subvols at their mountpoints underneath.
  local subvol mnt
  mount "$_LAYOUT_IMPL_ROOT_DEV" "$MOUNT_ROOT"
  while read -r subvol mnt; do
    btrfs subvolume create "${MOUNT_ROOT}/${subvol}"
  done < <(btrfs_root_subvols)
  umount "$MOUNT_ROOT"
  mount -o subvol=@ "$_LAYOUT_IMPL_ROOT_DEV" "$MOUNT_ROOT"
  while read -r subvol mnt; do
    [[ "$subvol" == "@" ]] && continue
    mkdir -p "${MOUNT_ROOT}${mnt}"
    mount -o "subvol=${subvol}" "$_LAYOUT_IMPL_ROOT_DEV" "${MOUNT_ROOT}${mnt}"
  done < <(btrfs_root_subvols)

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

  # fstab: one line per subvol (all share the one fs, differing by subvol=), then
  # the shared swap tail (which also sets LAYOUT_CRYPTTAB).
  local extra="# root + btrfs subvolumes"
  while read -r subvol mnt; do
    extra+=$'\n'"$(btrfs_subvol_fstab_line "$src" "$mnt" "$subvol")"
  done < <(btrfs_root_subvols)
  _nzroot_swap_tail "$enc"
  extra+="$_NZROOT_SWAP_FSTAB"
  # shellcheck disable=SC2034 # consumed by write_fstab
  LAYOUT_FSTAB_EXTRA="$extra"
  info "btrfs root + subvolumes formatted, mounted at $MOUNT_ROOT"
  _layout_exit_phase pools
}
