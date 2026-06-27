#!/usr/bin/env bash
# =============================================================================
# lib/layout/ext4/boot.sh — ext4 Root Adapter boot emitters (ADR 0043)
# =============================================================================
# Pure string functions the ext4 Root Adapter publishes into install-state so
# the FS-agnostic bootloader + initcpio can stay filesystem-blind:
#   - ext4_root_cmdline <root_uuid> → the `root=` fragment (the bootloader
#     appends ` rw` + the zswap fragment, as it does for ZFS).
#   - ext4_hooks                    → the mkinitcpio HOOKS list for a plaintext
#     ext4 root (no zfs hook; the `encrypt` hook lands with LUKS in a later
#     slice).
# Pure: no disk access.
# =============================================================================

# Root cmdline fragment for a plaintext ext4 root: boot by the filesystem UUID
# (stable across device-name reshuffles).
ext4_root_cmdline() {
  local root_uuid="$1"
  printf 'root=UUID=%s\n' "$root_uuid"
}

# mkinitcpio HOOKS for a plaintext ext4 root. `block` exposes device nodes
# before `filesystems` mounts the root; no `zfs` hook (no pool to import) and
# no `encrypt` (plaintext — LUKS adds it later).
ext4_hooks() {
  printf '%s\n' \
    "base udev autodetect microcode modconf kms block keyboard filesystems fsck"
}
