#!/usr/bin/env bats
# Validator-tier tests for the REAL fstab generators (ADR 0048, issue 04):
# _chroot_fstab_generate (lib/chroot.sh, ESP entries) + btrfs_root_fstab and
# data_group_fstab_line (the adapter tails). Their output is checked with a
# structural fstab lint (validators_fstab_lint) — field count, mountpoint
# plausibility, dump/pass ranges, and no duplicate mountpoint across the whole
# ASSEMBLED fstab, the thing nothing tests today (write_fstab concatenates ESP
# entries + the adapter's LAYOUT_FSTAB_EXTRA, and a clash only bites at boot).
#
# The existing chroot-fstab.bats keeps the business-value assertions (which UUID
# mounts where); this adds the structural verdict on real generator output.

setup() {
  load ../lib/validators
  TEST_DIR="$(mktemp -d)"
  FSTAB="$TEST_DIR/fstab"

  error() { echo "ERROR: $*" >&2; return 1; }
  local l="$BATS_TEST_DIRNAME/../.."
  # shellcheck source=../../lib/chroot.sh
  source "$l/lib/chroot.sh"
  # shellcheck source=../../lib/layout/btrfs/subvol.sh
  source "$l/lib/layout/btrfs/subvol.sh"
  # shellcheck source=../../lib/layout/nonzfs/data.sh
  source "$l/lib/layout/nonzfs/data.sh"

  U1=aaaaaaaa-0000-0000-0000-000000000001
  U2=bbbbbbbb-0000-0000-0000-000000000002
  U3=cccccccc-0000-0000-0000-000000000003
}
teardown() { rm -rf "$TEST_DIR"; }

# ── real ESP generator output lints clean (1/2/3 ESPs) ───────────────────────

@test "1-ESP fstab lints clean" {
  _chroot_fstab_generate "$U1" > "$FSTAB"
  run validators_fstab_lint "$FSTAB"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "3-ESP fstab (distinct /boot/efi mountpoints) lints clean" {
  _chroot_fstab_generate "$U1" "$U2" "$U3" > "$FSTAB"
  run validators_fstab_lint "$FSTAB"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

# ── real adapter tails lint clean ────────────────────────────────────────────

@test "btrfs root subvol fstab block lints clean" {
  btrfs_root_fstab "UUID=$U1" > "$FSTAB"
  run validators_fstab_lint "$FSTAB"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "data-group fstab line lints clean" {
  data_group_fstab_line "UUID=$U2" /mnt/tank ext4 > "$FSTAB"
  run validators_fstab_lint "$FSTAB"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

# btrfs multi/encrypted roots feed the same btrfs_root_fstab a mapper <src>
# (/dev/mapper/cryptroot) instead of a UUID — same generator, different device.
@test "btrfs root fstab over a mapper src lints clean" {
  btrfs_root_fstab /dev/mapper/cryptroot > "$FSTAB"
  run validators_fstab_lint "$FSTAB"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

# ── the ASSEMBLED fstab (ESP + btrfs root tail) — write_fstab's real shape ────

@test "assembled ESP + btrfs root fstab lints clean, no mountpoint clash" {
  {
    _chroot_fstab_generate "$U1"; echo; btrfs_root_fstab "UUID=$U2"
  } > "$FSTAB"
  run validators_fstab_lint "$FSTAB"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

# ── regressions: the lint has teeth ──────────────────────────────────────────

@test "regression: a duplicate mountpoint is rejected" {
  {
    _chroot_fstab_generate "$U1"
    echo "UUID=$U2  /boot/efi  vfat  umask=0077  0 2"   # clashes with the ESP
  } > "$FSTAB"
  run validators_fstab_lint "$FSTAB"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "duplicate mountpoint" ]]
}

@test "regression: a 5-field (malformed) line is rejected" {
  printf 'UUID=%s  /  btrfs  defaults  0\n' "$U1" > "$FSTAB"   # missing pass
  run validators_fstab_lint "$FSTAB"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "6 fields" ]]
}
