#!/usr/bin/env bash
# =============================================================================
# lib/layout/btrfs/subvol.sh — btrfs root subvolume layout (ADR 0043, issue 07)
# =============================================================================
# The pure declarations the btrfs Root Adapter iterates to create subvolumes,
# mount them, and write fstab. `layout_btrfs_root_subvolumes` is the single source of
# truth — the create loop and the fstab both read it, so they can't drift on
# which subvol mounts where. A flat-@ layout: @ is the root subvolume; @home /
# @log / @pkg / @snapshots split /home, the journal, the package cache, and
# snapshots out of the root subvolume up front (forward-compatible with the
# curated rollback subvols issue 08 adds per ADR 0044). Pure: no disk access.
# =============================================================================

# The curated rollback subvol list (impermanence_common_btrfs_rollback_subvolumes) lives in the
# FS-agnostic impermanence lib; fold it in here under impermanence. Sourced only
# (defines functions + the ROLLBACK_DATASETS source of truth, no side effects).
# shellcheck source=../../impermanence-common.sh
source "${BASH_SOURCE[0]%/*}/../../impermanence-common.sh"

# Emit `<subvol> <mountpoint>` per line — @ (root) first so the adapter mounts
# it before the nested subvols whose mountpoints live underneath it. The base OS
# layout; impermanence's rollback subvols are appended by _btrfs_subvol_all_root_subvolumes.
layout_btrfs_root_subvolumes() {
  printf '%s\n' \
    "@ /" \
    "@home /home" \
    "@log /var/log" \
    "@pkg /var/cache/pacman/pkg" \
    "@snapshots /.snapshots"
}

# True when impermanence is enabled for this install. Guarded so the pure base
# layout (unit tests that source only this file, no config accessors) reads as
# disabled instead of erroring; the real layout phase always has the accessor.
_btrfs_subvol_impermanence_on() {
  declare -F install_config_impermanence_enabled >/dev/null 2>&1 \
    && [[ "$(install_config_impermanence_enabled)" == "true" ]]
}

# The full subvol layout the create/mount loop + fstab iterate: the base OS
# subvols, plus the curated rollback subvols (@etc/@opt/@srv/@usrlocal)
# when impermanence is on so they are created+mounted before pacstrap AND land
# in fstab (the impermanence bind units order After= these subvol mounts).
_btrfs_subvol_all_root_subvolumes() {
  layout_btrfs_root_subvolumes
  _btrfs_subvol_impermanence_on && impermanence_common_btrfs_rollback_subvolumes
  return 0
}

# The /etc/fstab line one subvolume contributes. <src> is the shared mount
# source — `UUID=<fs-uuid>` (plaintext) or `/dev/mapper/cryptroot` (encrypted) —
# identical for every subvol since they share the one btrfs filesystem; the
# subvol= option is what differs. btrfs has no fsck, so dump/pass are 0 0. Pure.
layout_btrfs_subvolume_fstab_line() {
  local source_device="$1" mount="$2" subvol="$3"
  printf '%s  %s  btrfs  rw,relatime,subvol=%s  0 0\n' "$source_device" "$mount" "$subvol"
}

# The full fstab block for the root subvolume layout: one line per subvol off the
# shared mount <src> (`UUID=…` plaintext / `/dev/mapper/cryptroot` encrypted),
# @ → / first. Shared by the single- and multi-disk btrfs adapters so both emit
# identical fstab from the one layout. Pure.
layout_btrfs_root_fstab() {
  local source_device="$1" subvol mountpoint out=""
  while read -r subvol mountpoint; do
    out+="${out:+$'\n'}$(layout_btrfs_subvolume_fstab_line "$source_device" "$mountpoint" "$subvol")"
  done < <(_btrfs_subvol_all_root_subvolumes)
  printf '%s\n' "$out"
}

# Disk-touching: create the root subvolume layout on the formatted btrfs <root_dev>
# (single device or an assembled raid), then mount @ as the install root with the
# nested subvols at their mountpoints underneath. Shared by the single- and
# multi-disk btrfs adapters. Requires MOUNT_ROOT + btrfs-progs; VM-gated.
layout_btrfs_create_and_mount_subvolumes() {
  local root_dev="$1" subvol mountpoint
  mount "$root_dev" "$MOUNT_ROOT"
  while read -r subvol mountpoint; do
    btrfs subvolume create "${MOUNT_ROOT}/${subvol}"
  done < <(_btrfs_subvol_all_root_subvolumes)
  umount "$MOUNT_ROOT"
  mount -o subvol=@ "$root_dev" "$MOUNT_ROOT"
  while read -r subvol mountpoint; do
    [[ "$subvol" == "@" ]] && continue
    mkdir -p "${MOUNT_ROOT}${mountpoint}"
    mount -o "subvol=${subvol}" "$root_dev" "${MOUNT_ROOT}${mountpoint}"
  done < <(_btrfs_subvol_all_root_subvolumes)
}
