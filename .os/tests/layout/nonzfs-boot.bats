#!/usr/bin/env bats
# Tests for the non-ZFS Root Adapter boot emitters (ADR 0043) — the pure,
# filesystem-blind string functions every non-ZFS root (ext4/xfs) publishes:
# the `ROOT_CMDLINE` fragment and the initramfs `HOOKS` list. The cmdline + hooks
# carry no filesystem name (ext4 and xfs are byte-identical here); only the mkfs
# command and the fstab fs-type column differ per filesystem, and those live in
# the per-fs leaf, not in these emitters. The FS-agnostic bootloader appends
# ` rw` + the zswap fragment to ROOT_CMDLINE; initcpio.sh writes whatever HOOKS
# the adapter declares. An `encrypted` flag switches both to the LUKS variant.
# Pure: no disk access.

setup() {
  # shellcheck source=../../lib/layout/nonzfs/boot.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/nonzfs/boot.sh"
}

# ── ROOT_CMDLINE: a plaintext non-ZFS root boots by root UUID ────────────────

@test "nonzfs_root_cmdline: emits root=UUID for the given root uuid" {
  run nonzfs_root_cmdline "1234-ABCD"
  [ "$status" -eq 0 ]
  [ "$output" = "root=UUID=1234-ABCD" ]
}

# ── ROOT_CMDLINE: an encrypted non-ZFS root boots via the LUKS mapper ────────

@test "nonzfs_root_cmdline: encrypted emits cryptdevice + mapper root" {
  # The uuid is the LUKS container partition UUID; initramfs opens it as
  # 'cryptroot', then the root is /dev/mapper/cryptroot.
  run nonzfs_root_cmdline "1234-ABCD" encrypted
  [ "$status" -eq 0 ]
  [ "$output" = "cryptdevice=UUID=1234-ABCD:cryptroot root=/dev/mapper/cryptroot" ]
}

# ── HOOKS: a plaintext non-ZFS root needs no zfs / no encrypt hook ───────────

@test "nonzfs_hooks: includes block + filesystems, excludes zfs and encrypt" {
  run nonzfs_hooks
  [ "$status" -eq 0 ]
  [[ "$output" =~ "block" ]]
  [[ "$output" =~ "filesystems" ]]
  [[ ! "$output" =~ "zfs" ]]
  [[ ! "$output" =~ "encrypt" ]]
}

@test "nonzfs_hooks: block precedes filesystems (device nodes before mount)" {
  run nonzfs_hooks
  local hooks="$output"
  # crude ordering check: index of 'block' < index of 'filesystems'
  [[ "$hooks" =~ ^(.*)block(.*)filesystems(.*)$ ]]
}

# ── HOOKS: an encrypted non-ZFS root adds `encrypt` before `filesystems` ─────

@test "nonzfs_hooks: encrypted inserts encrypt between block and filesystems" {
  run nonzfs_hooks encrypted
  [ "$status" -eq 0 ]
  [[ "$output" =~ "encrypt" ]]
  # encrypt must open the container after block exposes it, before the mount.
  [[ "$output" =~ ^(.*)block(.*)encrypt(.*)filesystems(.*)$ ]]
}
