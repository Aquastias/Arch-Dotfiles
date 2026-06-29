#!/usr/bin/env bash
# =============================================================================
# lib/layout/btrfs/subvol.sh — btrfs root subvolume layout (ADR 0043, issue 07)
# =============================================================================
# The pure declarations the btrfs Root Adapter iterates to create subvolumes,
# mount them, and write fstab. `btrfs_root_subvols` is the single source of
# truth — the create loop and the fstab both read it, so they can't drift on
# which subvol mounts where. A flat-@ layout: @ is the root subvolume; @home /
# @log / @pkg / @snapshots split /home, the journal, the package cache, and
# snapshots out of the root subvolume up front (forward-compatible with the
# curated rollback subvols issue 08 adds per ADR 0044). Pure: no disk access.
# =============================================================================

# Emit `<subvol> <mountpoint>` per line — @ (root) first so the adapter mounts
# it before the nested subvols whose mountpoints live underneath it.
btrfs_root_subvols() {
  printf '%s\n' \
    "@ /" \
    "@home /home" \
    "@log /var/log" \
    "@pkg /var/cache/pacman/pkg" \
    "@snapshots /.snapshots"
}

# The /etc/fstab line one subvolume contributes. <src> is the shared mount
# source — `UUID=<fs-uuid>` (plaintext) or `/dev/mapper/cryptroot` (encrypted) —
# identical for every subvol since they share the one btrfs filesystem; the
# subvol= option is what differs. btrfs has no fsck, so dump/pass are 0 0. Pure.
btrfs_subvol_fstab_line() {
  local src="$1" mount="$2" subvol="$3"
  printf '%s  %s  btrfs  rw,relatime,subvol=%s  0 0\n' "$src" "$mount" "$subvol"
}

# The full fstab block for the root subvolume layout: one line per subvol off the
# shared mount <src> (`UUID=…` plaintext / `/dev/mapper/cryptroot` encrypted),
# @ → / first. Shared by the single- and multi-disk btrfs adapters so both emit
# identical fstab from the one layout. Pure.
btrfs_root_fstab() {
  local src="$1" subvol mnt out=""
  while read -r subvol mnt; do
    out+="${out:+$'\n'}$(btrfs_subvol_fstab_line "$src" "$mnt" "$subvol")"
  done < <(btrfs_root_subvols)
  printf '%s\n' "$out"
}

# Disk-touching: create the root subvolume layout on the formatted btrfs <root_dev>
# (single device or an assembled raid), then mount @ as the install root with the
# nested subvols at their mountpoints underneath. Shared by the single- and
# multi-disk btrfs adapters. Requires MOUNT_ROOT + btrfs-progs; VM-gated.
_btrfs_create_and_mount_subvols() {
  local root_dev="$1" subvol mnt
  mount "$root_dev" "$MOUNT_ROOT"
  while read -r subvol mnt; do
    btrfs subvolume create "${MOUNT_ROOT}/${subvol}"
  done < <(btrfs_root_subvols)
  umount "$MOUNT_ROOT"
  mount -o subvol=@ "$root_dev" "$MOUNT_ROOT"
  while read -r subvol mnt; do
    [[ "$subvol" == "@" ]] && continue
    mkdir -p "${MOUNT_ROOT}${mnt}"
    mount -o "subvol=${subvol}" "$root_dev" "${MOUNT_ROOT}${mnt}"
  done < <(btrfs_root_subvols)
}
