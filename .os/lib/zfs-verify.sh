#!/usr/bin/env bash
# =============================================================================
# lib/zfs-verify.sh — fail-fast ZFS Module Guard for the installed system
# =============================================================================
# Sourced by 03-install.sh. Requires: lib/common.sh already sourced.
#
# Runs host-side after pacstrap and before chroot configuration. It verifies a
# loadable `zfs` module exists for every kernel installed into the target and
# aborts early (with archzfs guidance) when one is missing — instead of the
# opaque mid-`mkinitcpio -P` "module not found: zfs" crash that motivated ADR
# 0024.
#
# This is distinct from lib/zfs-module.sh, which builds ZFS for the *live ISO*
# kernel (ADR 0023). This guard inspects the *target system's* kernels.
#
# Provides:
#   zfs_kernels_missing_module <modules_dir>  — pure: module tree in, set of
#                                               kernels (pkgbase flavour) that
#                                               lack a ZFS module out
#   zfs_verify_target_modules [target_root]   — thin guard: aborts (error) when
#                                               any target kernel lacks ZFS
# =============================================================================

# Guard against double-sourcing.
[[ -n "${_ZFS_VERIFY_SH_SOURCED:-}" ]] && return 0
_ZFS_VERIFY_SH_SOURCED=1

# True if a built ZFS module exists anywhere under a kernel's module tree.
# DKMS installs to <kver>/updates/dkms/zfs.ko*, archzfs prebuilts to
# <kver>/extra/zfs.ko*; a recursive match on zfs.ko* covers any compression
# suffix (.zst/.xz/none).
_zfs_module_present() {
  local kdir="$1"
  find "$kdir" -type f -name 'zfs.ko*' -print -quit 2>/dev/null | grep -q .
}

# Pure helper: given a module tree (e.g. <target>/usr/lib/modules), print the
# pkgbase flavour of every installed kernel that lacks a ZFS module, one per
# line, sorted-unique. Empty output means every kernel has one. Installed
# kernels are enumerated from their `pkgbase` markers — no hardcoded list. No
# DKMS rebuild is attempted; this only reports.
zfs_kernels_missing_module() {
  local modules_dir="${1:-/usr/lib/modules}"
  local marker kdir
  for marker in "$modules_dir"/*/pkgbase; do
    [[ -f "$marker" ]] || continue
    kdir="${marker%/pkgbase}"
    _zfs_module_present "$kdir" && continue
    printf '%s\n' "$(<"$marker")"
  done | sort -u
}

# Fail-fast guard. Runs host-side after pacstrap, before chroot configuration.
# Aborts the install (via error) when any kernel installed into target_root
# lacks a ZFS module, naming the offending kernel(s) and pointing at the
# archzfs constraint. Never attempts a DKMS rebuild — surfaces the real cause
# (archzfs lagging the chosen kernel) rather than masking it. Returns silently
# when every kernel has a module (the supported lts path is unchanged).
zfs_verify_target_modules() {
  local target_root="${1:-${MOUNT_ROOT:-/mnt}}"
  local missing
  missing="$(zfs_kernels_missing_module "${target_root}/usr/lib/modules")"
  [[ -z "$missing" ]] && return 0

  local list
  list="$(printf '%s' "$missing" | tr '\n' ' ')"
  list="${list% }"
  error "No ZFS kernel module was built for: ${list}.
  archzfs could not build zfs-dkms against this/these kernel(s). Left
  unchecked the install would crash later in 'mkinitcpio -P' with
  'module not found: zfs'. Fix: select an archzfs-supported kernel — 'lts'
  via options.kernel — or wait for archzfs to track ${list}.
  See ADR 0024 and the archzfs-Compatible ISO concept (ADR 0023)."
}
