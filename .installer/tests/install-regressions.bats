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

# ── errexit / ERR-trap class (bug scan 20261019) ─────────────────────────────

# _extract_function <file> <name> — print one top-level function definition.
_extract_function() {
  awk -v name="$2" '$0 ~ "^" name "\\(\\) \\{" { on = 1 } on { print }
    on && /^\}/ { exit }' "$1"
}

@test "bootstrap's route wait survives a slow DHCP under set -e" {
  local script="$BATS_TEST_TMPDIR/route.sh"
  {
    echo 'set -Eeuo pipefail'
    echo 'info() { :; }; ip() { return 1; }; sleep() { :; }'
    _extract_function "$R/01-bootstrap-zfs.sh" _wait_for_default_route
    echo '_wait_for_default_route; echo SURVIVED'
  } >"$script"
  run bash "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *SURVIVED* ]]
}

@test "the numbered scripts' ERR handlers stand down inside subshells" {
  # An `exit` from the trap inside a command substitution kills helpers bash
  # runs without errexit (a pool-owners counter aborted whole installs).
  local script
  for script in 01-bootstrap-zfs.sh 02-wipe.sh 03-install.sh; do
    _extract_function "$R/$script" _on_error \
      | grep -q 'BASH_SUBSHELL == 0' || { echo "unguarded: $script"; return 1; }
  done
}

@test "install.sh reads guided_build's status without tripping errexit" {
  # Save/Export return 64 on purpose; a bare call aborted before the check.
  grep -qE 'guided_build >"\$effective_config" \|\| guided_status=\$\?' \
    "$R/install.sh"
}

@test "install.sh validates the config before 02-wipe zeroes the disks" {
  local body check wipe
  body="$(_extract_function "$R/install.sh" run_numbered_phases)"
  check="$(awk '/03-install\.sh" --check/ { print NR; exit }' <<<"$body")"
  wipe="$(awk '/02-wipe\.sh/ { print NR; exit }' <<<"$body")"
  [ -n "$check" ] && [ -n "$wipe" ] && (( check < wipe ))
}

@test "03-install --check stops right after validation, before any disk phase" {
  local body check plan
  body="$(_extract_function "$R/03-install.sh" main)"
  check="$(awk '/INSTALL_CHECK_ONLY/ { print NR; exit }' <<<"$body")"
  plan="$(awk '/plan_and_confirm/ { print NR; exit }' <<<"$body")"
  [ -n "$check" ] && [ -n "$plan" ] && (( check < plan ))
}

@test "CleanMethod is set on the target after pacman.conf is copied over it" {
  local body copy clean
  body="$(_extract_function "$R/lib/chroot.sh" chroot_configure_system)"
  copy="$(awk '/cp \/etc\/pacman.conf/ { print NR; exit }' <<<"$body")"
  clean="$(awk '/CleanMethod = KeepCurrent/ { print NR; exit }' <<<"$body")"
  [ -n "$copy" ] && [ -n "$clean" ] && (( copy < clean ))
  ! grep -q 'CleanMethod' "$R/lib/packages/package-list.sh"
}
