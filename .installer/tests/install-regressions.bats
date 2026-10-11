#!/usr/bin/env bats
# Structural guards for install fixes from Audit Run 20261003 whose code is
# too system-bound (pacstrap, a live chroot) for a behavioural test.

R="$BATS_TEST_DIRNAME/.."

@test "pacman.conf reaches the target on every layout, not only ZFS" {
  # ext4/btrfs installs lost [multilib] when the copy sat in the zpool branch
  local body cp zfs
  body="$(awk '/^chroot_configure_system\(\) \{/, /^\}/' "$R/lib/chroot.sh")"
  cp="$(awk '/cp \/etc\/pacman.conf/ { print NR; exit }' <<<"$body")"
  # the ZFS-only seeding is its own step; the copy must come before it
  zfs="$(awk '/_chroot_seed_zfs_state/ { print NR }' <<<"$body")"
  [ -n "$cp" ] && [ -n "$zfs" ] && (( cp < zfs ))
}

@test "pacstrap is retried (one CDN blip must not end an install)" {
  grep -qE '^\s*_retry [0-9]+ "[0-9,]+" -- pacstrap ' \
    "$R/lib/packages/package-list.sh"
}
