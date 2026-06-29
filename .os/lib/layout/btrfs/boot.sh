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

# mkinitcpio HOOKS for a btrfs root. A single-disk btrfs root mounts with the
# shared fs-blind hooks (no scan needed). A multi-disk (raid) root must run
# `btrfs device scan` in the initramfs so every member is registered before the
# root mounts, so the `btrfs` hook is inserted just before `filesystems` (after
# `encrypt` when the root is also LUKS). No btrfs-rollback hook yet (issue 08).
btrfs_hooks() {
  local encrypted="${1:-}" multi="${2:-}" hooks
  hooks="$(nonzfs_hooks "$encrypted")"
  [[ "$multi" == "multi" ]] && hooks="${hooks/ filesystems/ btrfs filesystems}"
  printf '%s\n' "$hooks"
}
