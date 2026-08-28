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

# ── the whole fstab block: one line per subvol off the shared mount source ────
# Shared by the single- and multi-disk btrfs adapters so they emit identical
# fstab from the one subvol layout. All lines carry the same <src> (the subvols
# share the one btrfs filesystem); @ → / leads.

@test "btrfs_root_fstab: one line per subvol, @ → / first, shared src" {
  run btrfs_root_fstab "UUID=DEAD-BEEF"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "UUID=DEAD-BEEF  /  btrfs  rw,relatime,subvol=@  0 0" ]
  [ "${#lines[@]}" -eq 5 ]
  [[ "$output" =~ "UUID=DEAD-BEEF  /var/log  btrfs  rw,relatime,subvol=@log  0 0" ]]
  [[ "$output" =~ "UUID=DEAD-BEEF  /.snapshots  btrfs  rw,relatime,subvol=@snapshots  0 0" ]]
}

# ── impermanence: rollback subvols fold into the layout (issue 08, ADR 0044) ──
# When impermanence is enabled the curated rollback subvols (@etc/@root/@opt/
# @srv/@usrlocal) join the base layout so the create+mount loop populates them
# before pacstrap AND fstab mounts them at boot (the bind units order After=
# these). The gate is the install_config accessor, guarded so the pure base
# layout (existing tests, no accessor) is unchanged.

@test "btrfs_root_fstab: rollback subvol lines added when impermanence on" {
  install_config_impermanence_enabled() { echo true; }
  run btrfs_root_fstab "UUID=DEAD-BEEF"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 10 ]
  [[ "$output" =~ "UUID=DEAD-BEEF  /etc  btrfs  rw,relatime,subvol=@etc  0 0" ]]
  [[ "$output" =~ "UUID=DEAD-BEEF  /usr/local  btrfs  rw,relatime,subvol=@usrlocal  0 0" ]]
}

@test "btrfs_root_fstab: no rollback lines when impermanence off" {
  install_config_impermanence_enabled() { echo false; }
  run btrfs_root_fstab "UUID=DEAD-BEEF"
  [ "${#lines[@]}" -eq 5 ]
  ! [[ "$output" =~ "subvol=@etc" ]]
}

# ── create+mount loop folds rollback subvols in under impermanence ───────────
# Disk-touching path with btrfs/mount/umount stubbed: the rollback subvols are
# `btrfs subvolume create`d (top-level pass) and mounted at their paths so
# pacstrap populates them before the @blank snapshot freezes them.

@test "_btrfs_create_and_mount_subvols: creates+mounts rollback subvols (imperm)" {
  install_config_impermanence_enabled() { echo true; }
  CALLS="$BATS_TEST_TMPDIR/calls.log"; : > "$CALLS"
  MOUNT_ROOT="$BATS_TEST_TMPDIR/mnt"; mkdir -p "$MOUNT_ROOT"
  btrfs()  { printf 'btrfs %s\n'  "$*" >> "$CALLS"; }
  mount()  { printf 'mount %s\n'  "$*" >> "$CALLS"; }
  umount() { printf 'umount %s\n' "$*" >> "$CALLS"; }
  _btrfs_create_and_mount_subvols /dev/sdX
  grep -qE "^btrfs subvolume create .*/@etc$"      "$CALLS"
  grep -qE "^btrfs subvolume create .*/@usrlocal$" "$CALLS"
  grep -qE "^mount -o subvol=@etc /dev/sdX .*/etc$" "$CALLS"
  grep -qE "^mount -o subvol=@usrlocal /dev/sdX .*/usr/local$" "$CALLS"
}

@test "_btrfs_create_and_mount_subvols: no rollback subvols when imperm off" {
  install_config_impermanence_enabled() { echo false; }
  CALLS="$BATS_TEST_TMPDIR/calls.log"; : > "$CALLS"
  MOUNT_ROOT="$BATS_TEST_TMPDIR/mnt"; mkdir -p "$MOUNT_ROOT"
  btrfs()  { printf 'btrfs %s\n'  "$*" >> "$CALLS"; }
  mount()  { printf 'mount %s\n'  "$*" >> "$CALLS"; }
  umount() { printf 'umount %s\n' "$*" >> "$CALLS"; }
  _btrfs_create_and_mount_subvols /dev/sdX
  ! grep -qE "@etc" "$CALLS"
}
