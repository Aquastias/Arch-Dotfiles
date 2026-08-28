#!/usr/bin/env bash
# =============================================================================
# lib/layout/nonzfs/boot.sh — non-ZFS Root Adapter boot emitters (ADR 0043)
# =============================================================================
# Pure, filesystem-blind string functions every non-ZFS Root Adapter (ext4/xfs)
# publishes into install-state so the FS-agnostic bootloader + initcpio stay
# filesystem-blind:
#   - nonzfs_root_cmdline <root_uuid> [encrypted] → the `root=` fragment (the
#     bootloader appends ` rw` + the zswap fragment, as it does for ZFS).
#   - nonzfs_hooks [encrypted]                    → the mkinitcpio HOOKS list.
# ext4 and xfs are byte-identical here (the cmdline/hooks carry no fs name); the
# only per-fs difference — mkfs + the fstab fs-type column — lives in the leaf
# (lib/layout/<fs>/single.sh). Pure: no disk access.
# =============================================================================

# Root cmdline fragment for a non-ZFS root. Plaintext boots by the filesystem
# UUID (stable across device-name reshuffles). With `encrypted`, the UUID is
# the LUKS *container* partition's UUID: the `encrypt` hook opens it as
# `cryptroot`, and the root is the resulting mapper device.
nonzfs_root_cmdline() {
  local uuid="$1" encrypted="${2:-}"
  if [[ "$encrypted" == "encrypted" ]]; then
    printf 'cryptdevice=UUID=%s:cryptroot root=/dev/mapper/cryptroot\n' "$uuid"
  else
    printf 'root=UUID=%s\n' "$uuid"
  fi
}

# mkinitcpio HOOKS for a non-ZFS root. `block` exposes device nodes before
# `filesystems` mounts the root; no `zfs` hook (no pool to import). With
# `encrypted`, the `encrypt` hook is inserted between them so the LUKS
# container is opened before the root is mounted.
nonzfs_hooks() {
  local encrypted="${1:-}" crypt=""
  [[ "$encrypted" == "encrypted" ]] && crypt="encrypt "
  printf '%s\n' \
    "base udev autodetect microcode modconf kms block keyboard ${crypt}filesystems fsck"
}
