#!/usr/bin/env bats
# Tests for the btrfs Root Adapter boot emitter (ADR 0043, issue 07) — the pure
# `ROOT_CMDLINE` fragment for a btrfs root. Unlike ext4/xfs (which boot a bare
# root device), btrfs boots a *subvolume*, so the cmdline carries
# `rootflags=subvol=<subvol>` in addition to the root= the encrypt/plaintext
# switch produces. HOOKS for a single-disk btrfs root are the shared, fs-blind
# layout_nonzfs_hooks (no zfs, no btrfs-rollback yet — that lands in issue 08). Pure:
# no disk access.

setup() {
  # shellcheck source=../../lib/layout/btrfs/boot.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/btrfs/boot.sh"
}

# ── ROOT_CMDLINE: a plaintext btrfs root boots the @ subvolume by fs UUID ─────

@test "layout_btrfs_root_cmdline: plaintext emits root=UUID + rootflags=subvol" {
  run layout_btrfs_root_cmdline "1234-ABCD" @
  [ "$status" -eq 0 ]
  [ "$output" = "root=UUID=1234-ABCD rootflags=subvol=@" ]
}

# ── ROOT_CMDLINE: an encrypted btrfs root boots the @ subvol via the mapper ───

@test "layout_btrfs_root_cmdline: encrypted emits cryptdevice + mapper + rootflags" {
  # The uuid is the LUKS container partition UUID; initramfs opens it as
  # 'cryptroot', then the root is the @ subvolume on /dev/mapper/cryptroot.
  run layout_btrfs_root_cmdline "1234-ABCD" @ encrypted
  [ "$status" -eq 0 ]
  [ "$output" = "cryptdevice=UUID=1234-ABCD:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@" ]
}

# ── HOOKS: single-disk btrfs needs no btrfs scan hook (shared nonzfs hooks) ───

@test "layout_btrfs_hooks: single-disk omits the btrfs scan hook" {
  run layout_btrfs_hooks
  [ "$status" -eq 0 ]
  [[ "$output" =~ "filesystems" ]]
  [[ ! "$output" =~ "btrfs" ]]
}

# ── HOOKS: multi-disk btrfs adds the `btrfs` scan hook before `filesystems` ───
# A multi-device btrfs root must run `btrfs device scan` in the initramfs so the
# raid assembles before the root is mounted.

@test "layout_btrfs_hooks: multi-disk inserts btrfs before filesystems" {
  run layout_btrfs_hooks "" multi
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^(.*)block(.*)btrfs(.*)filesystems(.*)$ ]]
}

@test "layout_btrfs_hooks: encrypted multi keeps encrypt then btrfs then filesystems" {
  run layout_btrfs_hooks encrypted multi
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^(.*)encrypt(.*)btrfs(.*)filesystems(.*)$ ]]
}

# ── HOOKS: impermanence inserts btrfs-rollback before filesystems (issue 08) ──
# The boot-time rollback hook must run before `filesystems` pivots into root.
# Its run_hook needs the btrfs binary in the image, so impermanence also pulls in
# the `btrfs` hook (harmless as a scan on a single device) — never duplicated on
# multi-disk where `btrfs` is already present.

@test "layout_btrfs_hooks: single + impermanence → btrfs btrfs-rollback before filesystems" {
  run layout_btrfs_hooks "" "" impermanence
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^(.*)btrfs\ btrfs-rollback\ filesystems(.*)$ ]]
}

@test "layout_btrfs_hooks: multi + impermanence → single btrfs then btrfs-rollback" {
  run layout_btrfs_hooks "" multi impermanence
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^(.*)block(.*)btrfs\ btrfs-rollback\ filesystems(.*)$ ]]
  # btrfs must not be duplicated
  [ "$(grep -oc 'btrfs ' <<<"$output")" -eq 1 ]
}

@test "layout_btrfs_hooks: encrypted single + impermanence keeps encrypt first" {
  run layout_btrfs_hooks encrypted "" impermanence
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^(.*)encrypt(.*)btrfs\ btrfs-rollback\ filesystems(.*)$ ]]
}

@test "layout_btrfs_hooks: no impermanence → no btrfs-rollback hook" {
  run layout_btrfs_hooks "" multi
  [[ ! "$output" =~ "btrfs-rollback" ]]
}
