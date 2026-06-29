#!/usr/bin/env bash
# =============================================================================
# lib/layout/btrfs/boot.sh — btrfs Root Adapter boot emitter (ADR 0043)
# =============================================================================
# The pure `ROOT_CMDLINE` fragment for a btrfs root. A btrfs root boots a
# *subvolume*, not a bare device, so the cmdline carries
# `rootflags=subvol=<subvol>` on top of the root= the shared non-ZFS emitter
# produces (root=UUID plaintext / cryptdevice=…:cryptroot encrypted). The
# initramfs HOOKS for a single-disk btrfs root are the shared, fs-blind
# nonzfs_hooks — no zfs hook, and no btrfs-rollback hook yet (that lands with
# impermanence in issue 08). Pure: no disk access.
# =============================================================================

# shellcheck source=../nonzfs/boot.sh
source "${BASH_SOURCE[0]%/*}/../nonzfs/boot.sh"

# Root cmdline fragment for a btrfs root mounting <subvol> as /. Reuses the
# shared non-ZFS root= (plaintext UUID or encrypted LUKS mapper), then appends
# the subvolume selector the initramfs needs to mount the right subvol as root.
btrfs_root_cmdline() {
  local uuid="$1" subvol="$2" encrypted="${3:-}"
  printf '%s rootflags=subvol=%s\n' \
    "$(nonzfs_root_cmdline "$uuid" "$encrypted")" "$subvol"
}
