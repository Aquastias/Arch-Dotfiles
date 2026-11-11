#!/usr/bin/env bats
# Structural guards for install fixes from Audit Run 20261003 whose code is
# too system-bound (pacstrap, a live chroot) for a behavioural test.

R="$BATS_TEST_DIRNAME/.."

# _extract_function <file> <name> — print one top-level function definition:
# from its "<name>() {" line to the first line starting with "}".
_extract_function() {
  local line printing=0
  while IFS= read -r line; do
    [[ "$line" == "$2() {"* ]] && printing=1
    (( printing )) || continue
    printf '%s\n' "$line"
    [[ "$line" == "}"* ]] && return 0
  done < "$1"
  return 0
}

# _line_of <text> <words> — the number of the first line of <text> that
# contains <words> ("" when no line does).
_line_of() {
  local -a text_lines
  local i
  mapfile -t text_lines < <(printf '%s\n' "$1")
  for i in "${!text_lines[@]}"; do
    if [[ "${text_lines[i]}" == *"$2"* ]]; then
      printf '%s\n' "$((i + 1))"
      return 0
    fi
  done
}

@test "pacman.conf reaches the target on every layout, not only ZFS" {
  # ext4/btrfs installs lost [multilib] when the copy sat in the zpool branch
  local body cp zfs
  body="$(_extract_function "$R/lib/chroot.sh" chroot_configure_system)"
  cp="$(_line_of "$body" "cp /etc/pacman.conf")"
  # the ZFS-only seeding is its own step; the copy must come before it
  zfs="$(_line_of "$body" _chroot_seed_zfs_state)"
  [ -n "$cp" ] && [ -n "$zfs" ] && (( cp < zfs ))
}

@test "pacstrap is retried (one CDN blip must not end an install)" {
  grep -qE '^\s*_retry [0-9]+ "[0-9,]+" -- pacstrap ' \
    "$R/lib/packages/package-list.sh"
}

# ── errexit / ERR-trap class (bug scan 20261019) ─────────────────────────────

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
  check="$(_line_of "$body" '03-install.sh" --check')"
  wipe="$(_line_of "$body" 02-wipe.sh)"
  [ -n "$check" ] && [ -n "$wipe" ] && (( check < wipe ))
}

@test "03-install --check stops right after validation, before any disk phase" {
  local body check plan
  body="$(_extract_function "$R/03-install.sh" main)"
  check="$(_line_of "$body" INSTALL_CHECK_ONLY)"
  plan="$(_line_of "$body" plan_and_confirm)"
  [ -n "$check" ] && [ -n "$plan" ] && (( check < plan ))
}

@test "CleanMethod is set on the target after pacman.conf is copied over it" {
  local body copy clean
  body="$(_extract_function "$R/lib/chroot.sh" chroot_configure_system)"
  copy="$(_line_of "$body" "cp /etc/pacman.conf")"
  clean="$(_line_of "$body" "CleanMethod = KeepCurrent")"
  [ -n "$copy" ] && [ -n "$clean" ] && (( copy < clean ))
  ! grep -q 'CleanMethod' "$R/lib/packages/package-list.sh"
}
