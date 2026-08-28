#!/usr/bin/env bash
# =============================================================================
# lib/packages/filesystem.sh — Filesystem userland package map (pure)
# =============================================================================
# Maps a filesystem token to the userland tools a group using it needs, plus the
# LUKS userland for a non-ZFS encrypted group. Pure: shared by the install path
# (list.sh's collect_packages) and the Package Resolver (resolver.sh), so the
# package NAMES live once. Each caller keeps its own DECISION of which
# filesystems are present (accessors vs config parse); this is only the names.
#
#   zfs   → zfs-dkms zfs-utils  (dkms builds against installed kernel headers)
#   xfs   → xfsprogs            (ext4 rides e2fsprogs in base; zfs has no mkfs)
#   btrfs → btrfs-progs
# LUKS (dm-crypt) userland is filesystem-independent — ZFS uses native crypto.
# =============================================================================

[[ -n "${_FILESYSTEM_SH_SOURCED:-}" ]] && return 0
_FILESYSTEM_SH_SOURCED=1

# fs_userland_packages <fs> → space-separated userland tools (may be empty).
fs_userland_packages() {
  case "$1" in
    zfs)   echo "zfs-dkms zfs-utils" ;;
    xfs)   echo "xfsprogs" ;;
    btrfs) echo "btrfs-progs" ;;
  esac
}

# luks_userland_packages → the dm-crypt userland for a non-ZFS encrypted group.
luks_userland_packages() { echo "cryptsetup"; }
