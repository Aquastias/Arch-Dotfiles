#!/usr/bin/env bats
# Tests for the btrfs root subvolume layout (ADR 0043, issue 07) — the pure
# declarations the disk-touching adapter iterates to create subvolumes, mount
# them, and write fstab. One source of truth (btrfs_root_subvols) drives both
# the `btrfs subvolume create` loop and the fstab so they can't drift. The
# richer flat-@ layout keeps logs / package cache / snapshots out of the root
# subvolume up front (forward-compatible with the curated rollback subvols issue
# 08 adds per ADR 0044). Pure: string emitters, no disk access.

setup() {
  # shellcheck source=../../lib/layout/btrfs/subvol.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/btrfs/subvol.sh"
}

# ── the subvolume layout: <subvol> <mountpoint> per line, @ → / first ─────────

@test "btrfs_root_subvols: @ mounts / first (the root subvol)" {
  run btrfs_root_subvols
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "@ /" ]
}

@test "btrfs_root_subvols: carries the richer split (home/log/pkg/snapshots)" {
  run btrfs_root_subvols
  [ "$status" -eq 0 ]
  [[ "$output" =~ "@home /home" ]]
  [[ "$output" =~ "@log /var/log" ]]
  [[ "$output" =~ "@pkg /var/cache/pacman/pkg" ]]
  [[ "$output" =~ "@snapshots /.snapshots" ]]
}

# ── fstab line: every subvol shares the one btrfs fs, differing only by subvol=
# All subvols live on the same btrfs filesystem, so the source (UUID plaintext /
# mapper encrypted) is identical per line; only the subvol= mount option differs.
# btrfs has no fsck, so the dump/pass columns are 0 0.

@test "btrfs_subvol_fstab_line: plaintext root mounts @ by UUID, subvol opt" {
  run btrfs_subvol_fstab_line "UUID=DEAD-BEEF" / @
  [ "$status" -eq 0 ]
  [ "$output" = "UUID=DEAD-BEEF  /  btrfs  rw,relatime,subvol=@  0 0" ]
}

@test "btrfs_subvol_fstab_line: encrypted root mounts the mapper, subvol opt" {
  run btrfs_subvol_fstab_line /dev/mapper/cryptroot /home @home
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/mapper/cryptroot  /home  btrfs  rw,relatime,subvol=@home  0 0" ]
}
