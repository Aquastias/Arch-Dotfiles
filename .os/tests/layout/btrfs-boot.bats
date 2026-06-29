#!/usr/bin/env bats
# Tests for the btrfs Root Adapter boot emitter (ADR 0043, issue 07) — the pure
# `ROOT_CMDLINE` fragment for a btrfs root. Unlike ext4/xfs (which boot a bare
# root device), btrfs boots a *subvolume*, so the cmdline carries
# `rootflags=subvol=<subvol>` in addition to the root= the encrypt/plaintext
# switch produces. HOOKS for a single-disk btrfs root are the shared, fs-blind
# nonzfs_hooks (no zfs, no btrfs-rollback yet — that lands in issue 08). Pure:
# no disk access.

setup() {
  # shellcheck source=../../lib/layout/btrfs/boot.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/btrfs/boot.sh"
}

# ── ROOT_CMDLINE: a plaintext btrfs root boots the @ subvolume by fs UUID ─────

@test "btrfs_root_cmdline: plaintext emits root=UUID + rootflags=subvol" {
  run btrfs_root_cmdline "1234-ABCD" @
  [ "$status" -eq 0 ]
  [ "$output" = "root=UUID=1234-ABCD rootflags=subvol=@" ]
}

# ── ROOT_CMDLINE: an encrypted btrfs root boots the @ subvol via the mapper ───

@test "btrfs_root_cmdline: encrypted emits cryptdevice + mapper + rootflags" {
  # The uuid is the LUKS container partition UUID; initramfs opens it as
  # 'cryptroot', then the root is the @ subvolume on /dev/mapper/cryptroot.
  run btrfs_root_cmdline "1234-ABCD" @ encrypted
  [ "$status" -eq 0 ]
  [ "$output" = "cryptdevice=UUID=1234-ABCD:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@" ]
}
