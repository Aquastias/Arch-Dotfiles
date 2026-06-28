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

# Root cmdline fragment for an ext4 root. Plaintext boots by the filesystem
# UUID (stable across device-name reshuffles). With `encrypted`, the UUID is
# the LUKS *container* partition's UUID: the `encrypt` hook opens it as
# `cryptroot`, and the root is the resulting mapper device.
ext4_root_cmdline() {
  local uuid="$1" encrypted="${2:-}"
  if [[ "$encrypted" == "encrypted" ]]; then
    printf 'cryptdevice=UUID=%s:cryptroot root=/dev/mapper/cryptroot\n' "$uuid"
  else
    printf 'root=UUID=%s\n' "$uuid"
  fi
}

# mkinitcpio HOOKS for an ext4 root. `block` exposes device nodes before
# `filesystems` mounts the root; no `zfs` hook (no pool to import). With
# `encrypted`, the `encrypt` hook is inserted between them so the LUKS
# container is opened before the root is mounted.
ext4_hooks() {
  local encrypted="${1:-}" crypt=""
  [[ "$encrypted" == "encrypted" ]] && crypt="encrypt "
  printf '%s\n' \
    "base udev autodetect microcode modconf kms block keyboard ${crypt}filesystems fsck"
}
