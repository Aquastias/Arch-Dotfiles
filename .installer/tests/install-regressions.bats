#!/usr/bin/env bats
# Structural guards for install fixes from Audit Run 20261003 whose code is
# too system-bound (pacstrap, a live chroot) for a behavioural test.

R="$BATS_TEST_DIRNAME/.."

@test "pacman.conf reaches the target on every layout, not only ZFS" {
  # ext4/btrfs installs lost [multilib] when the copy sat in the zpool branch
  local body cp zfs
  body="$(sed -n '/^configure_system() {/,/^}/p' "$R/lib/chroot.sh")"
  cp="$(grep -n 'cp /etc/pacman.conf' <<<"$body" | head -1 | cut -d: -f1)"
  zfs="$(grep -n 'if command_exists zpool' <<<"$body" | cut -d: -f1)"
  [ -n "$cp" ] && [ -n "$zfs" ] && (( cp < zfs ))
}

@test "pacstrap is retried (one CDN blip must not end an install)" {
  grep -qE '^\s*_retry [0-9]+ "[0-9,]+" -- pacstrap ' \
    "$R/lib/packages/list.sh"
}
