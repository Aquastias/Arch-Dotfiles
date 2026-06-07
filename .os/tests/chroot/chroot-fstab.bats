#!/usr/bin/env bats
# Tests for _chroot_fstab_generate() in lib/chroot.sh.
#
# Strategy: source chroot.sh with common.sh helpers stubbed, then call
# _chroot_fstab_generate directly with fake UUIDs — no real disk or chroot.
# Tests cover 1-ESP and N-ESP branches independently.

setup() {
  error()   { echo "ERROR: $*" >&2; exit 1; }
  info()    { :; }
  warn()    { :; }
  section() { :; }

  # shellcheck source=../../lib/chroot.sh
  source "$BATS_TEST_DIRNAME/../../lib/chroot.sh"

  UUID1="aaaaaaaa-0000-0000-0000-000000000001"
  UUID2="bbbbbbbb-0000-0000-0000-000000000002"
  UUID3="cccccccc-0000-0000-0000-000000000003"
}

# ── guard: zero UUIDs is an error ────────────────────────────────────────────

@test "no UUIDs: exits non-zero with a message" {
  run _chroot_fstab_generate
  [ "$status" -ne 0 ]
  [[ "$output" =~ "no UUIDs provided" ]]
}

# ── 1-ESP branch ─────────────────────────────────────────────────────────────

@test "1 ESP: exits zero" {
  run _chroot_fstab_generate "$UUID1"
  [ "$status" -eq 0 ]
}

@test "1 ESP: contains the UUID" {
  run _chroot_fstab_generate "$UUID1"
  [[ "$output" =~ "UUID=$UUID1" ]]
}

@test "1 ESP: mounts at /boot/efi" {
  run _chroot_fstab_generate "$UUID1"
  [[ "$output" =~ "/boot/efi" ]]
  [[ ! "$output" =~ "/boot/efi1" ]]
}

@test "1 ESP: uses vfat with umask=0077" {
  run _chroot_fstab_generate "$UUID1"
  [[ "$output" =~ "vfat  umask=0077" ]]
}

@test "1 ESP: no 'secondary' comment present" {
  run _chroot_fstab_generate "$UUID1"
  [[ ! "$output" =~ "secondary" ]]
}

@test "1 ESP: ends with ZFS auto-mount comment" {
  run _chroot_fstab_generate "$UUID1"
  [[ "$output" =~ "zfs-mount-generator" ]]
}

# ── 2-ESP branch ─────────────────────────────────────────────────────────────

@test "2 ESPs: exits zero" {
  run _chroot_fstab_generate "$UUID1" "$UUID2"
  [ "$status" -eq 0 ]
}

@test "2 ESPs: primary UUID at /boot/efi" {
  run _chroot_fstab_generate "$UUID1" "$UUID2"
  [[ "$output" =~ "UUID=$UUID1  /boot/efi " ]]
}

@test "2 ESPs: secondary UUID at /boot/efi1" {
  run _chroot_fstab_generate "$UUID1" "$UUID2"
  [[ "$output" =~ "UUID=$UUID2  /boot/efi1 " ]]
}

@test "2 ESPs: secondary 1 comment present" {
  run _chroot_fstab_generate "$UUID1" "$UUID2"
  [[ "$output" =~ "secondary 1" ]]
}

@test "2 ESPs: ends with ZFS auto-mount comment" {
  run _chroot_fstab_generate "$UUID1" "$UUID2"
  [[ "$output" =~ "zfs-mount-generator" ]]
}

# ── 3-ESP branch ─────────────────────────────────────────────────────────────

@test "3 ESPs: all three UUIDs present" {
  run _chroot_fstab_generate "$UUID1" "$UUID2" "$UUID3"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "UUID=$UUID1" ]]
  [[ "$output" =~ "UUID=$UUID2" ]]
  [[ "$output" =~ "UUID=$UUID3" ]]
}

@test "3 ESPs: secondary 1 and secondary 2 comments present" {
  run _chroot_fstab_generate "$UUID1" "$UUID2" "$UUID3"
  [[ "$output" =~ "secondary 1" ]]
  [[ "$output" =~ "secondary 2" ]]
}

@test "3 ESPs: primary UUID not duplicated in secondary slots" {
  run _chroot_fstab_generate "$UUID1" "$UUID2" "$UUID3"
  primary_line="$(printf '%s\n' "$output" | grep "UUID=$UUID1")"
  # Primary line must mount at /boot/efi (not /boot/efi1 or /boot/efi2)
  [[ "$primary_line" =~ "/boot/efi " ]]
  [[ ! "$primary_line" =~ "/boot/efi[0-9]" ]]
}
