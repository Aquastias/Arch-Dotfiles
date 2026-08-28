#!/usr/bin/env bats
# Tests for the xfs Root Adapter (ADR 0043, issue 06) — a thin leaf over the
# shared non-ZFS root spine (lib/layout/nonzfs/root.sh). xfs is the same single-
# disk shape as ext4; the only filesystem-specific bits are the mkfs command
# (mkfs.xfs) and the fstab fs-type column, both supplied by this leaf as
# `_root_mkfs` / `_root_fstype`. The boot record it publishes (ROOT_CMDLINE +
# HOOKS) comes from the shared, fs-blind emitters, so an xfs root boots by root
# UUID (plaintext) or via the LUKS mapper (encrypted), exactly like ext4. Pure:
# sourcing the leaf only defines functions; no disk access.

setup() {
  # shellcheck source=../../lib/layout/xfs/single.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/xfs/single.sh"
}

# ── the leaf's filesystem-specific contract ──────────────────────────────────

@test "xfs leaf: _root_fstype is xfs (the fstab fs-type column)" {
  run _root_fstype
  [ "$status" -eq 0 ]
  [ "$output" = "xfs" ]
}

# ── ROOT_CMDLINE the xfs root publishes (shared emitter) ─────────────────────

@test "xfs root cmdline: plaintext boots by root UUID" {
  run nonzfs_root_cmdline "1234-ABCD"
  [ "$status" -eq 0 ]
  [ "$output" = "root=UUID=1234-ABCD" ]
}

@test "xfs root cmdline: encrypted boots via the LUKS mapper" {
  run nonzfs_root_cmdline "1234-ABCD" encrypted
  [ "$status" -eq 0 ]
  [ "$output" = "cryptdevice=UUID=1234-ABCD:cryptroot root=/dev/mapper/cryptroot" ]
}

# ── HOOKS the xfs root publishes (shared emitter) ────────────────────────────

@test "xfs root hooks: plaintext has block + filesystems, no zfs/encrypt" {
  run nonzfs_hooks
  [ "$status" -eq 0 ]
  [[ "$output" =~ "block" ]]
  [[ "$output" =~ "filesystems" ]]
  [[ ! "$output" =~ "zfs" ]]
  [[ ! "$output" =~ "encrypt" ]]
}

@test "xfs root hooks: encrypted inserts encrypt between block and filesystems" {
  run nonzfs_hooks encrypted
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^(.*)block(.*)encrypt(.*)filesystems(.*)$ ]]
}
