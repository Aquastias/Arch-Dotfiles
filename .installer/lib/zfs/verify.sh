#!/usr/bin/env bash
# =============================================================================
# lib/zfs/verify.sh — fail-fast ZFS Module Guard for the installed system
# =============================================================================
# Sourced by 03-install.sh. Requires: lib/common.sh already sourced.
#
# Runs host-side after pacstrap and before chroot configuration. It verifies a
# loadable `zfs` module exists for every kernel installed into the target and
# aborts early (with archzfs guidance) when one is missing — instead of the
# opaque mid-`mkinitcpio -P` "module not found: zfs" crash that motivated ADR
# 0024.
#
# This is distinct from lib/zfs/module.sh, which builds ZFS for the *live ISO*
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

# Pure: intersect the missing-set (one pkgbase per line) with the selected
# package bases (remaining args) — the Kernel Selection kernels that lack a ZFS
# module (the ABORT set). A Stray Kernel (missing but not selected) is excluded.
# One per line, sorted-unique. No args ⇒ empty selection ⇒ empty abort set.
zfs_missing_selected_kernels() {
  local missing_text="$1"; shift
  local -A selected=(); local s
  for s in "$@"; do selected["$s"]=1; done
  local k
  # An `if` (not `[[…]] && printf`) so the loop body's last command always exits
  # 0 — otherwise a trailing stray makes the loop return 1, and under the
  # installer's `set -Eeuo pipefail` the `| sort -u` pipe (pipefail) then fails
  # the `$(…)` capture and aborts the guard.
  while IFS= read -r k; do
    if [[ -n "$k" && -n "${selected[$k]:-}" ]]; then printf '%s\n' "$k"; fi
  done <<<"$missing_text" | sort -u
}

# Fail-fast guard. Runs host-side after pacstrap, before chroot configuration.
#
#   zfs_verify_target_modules <target_root> [selected_pkgbase...]
#
# Aborts the install (via error) only when a kernel in the Kernel Selection
# (selected_pkgbase args) lacks a ZFS module — the case that would crash
# 'mkinitcpio -P' with 'module not found: zfs' for a kernel we deliberately
# chose. A Stray Kernel (installed as a dependency, not in the selection, e.g.
# a rolling `linux` pulled in by wine on an lts host) that lacks a module is
# TOLERATED: warned here, non-fatal — its preset is dropped before mkinitcpio,
# it never reaches the ESP, and it is never the default boot (ADR 0138, amending
# ADR 0024). Never attempts a DKMS rebuild. Returns silently when every selected
# kernel has a module (the supported lts path is unchanged).
zfs_verify_target_modules() {
  local target_root="${1:-${MOUNT_ROOT:-/mnt}}"; shift 2>/dev/null || true
  local missing
  missing="$(zfs_kernels_missing_module "${target_root}/usr/lib/modules")"
  [[ -z "$missing" ]] && return 0

  local abort_set
  abort_set="$(zfs_missing_selected_kernels "$missing" "$@")"

  # Warn (non-fatal) about strays that lack a module — every missing kernel not
  # in the abort set.
  local k
  while IFS= read -r k; do
    [[ -n "$k" ]] || continue
    printf '%s\n' "$abort_set" | grep -qxF "$k" && continue
    warn "Stray Kernel '${k}' has no zfs.ko — tolerated. It is not in the
  Kernel Selection, is dropped before mkinitcpio, never reaches the ESP, and is
  never the default boot; it will not block this install (ADR 0138)."
  done <<<"$missing"

  [[ -z "$abort_set" ]] && return 0

  local list
  list="$(printf '%s' "$abort_set" | tr '\n' ' ')"
  list="${list% }"
  error "No ZFS kernel module was built for: ${list}.
  archzfs could not build zfs-dkms against this/these SELECTED kernel(s). Left
  unchecked the install would crash later in 'mkinitcpio -P' with
  'module not found: zfs'. Fix: select an archzfs-supported kernel — 'lts'
  via options.kernel — or wait for archzfs to track ${list}.
  See ADR 0024/0138 and the archzfs-Compatible ISO concept (ADR 0023)."
}
