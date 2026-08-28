#!/usr/bin/env bash
# =============================================================================
# lib/boot/stray-kernel.sh — Stray Kernel detector (ADR 0038)
# =============================================================================
# A Stray Kernel is a kernel installed but not in the host's Kernel Selection
# (e.g. a rolling `linux` pulled in out-of-band on an lts-only host). This
# surfaces strays and kernels missing zfs.ko, non-blockingly, from a
# PostTransaction pacman hook — it never removes a kernel or fails a
# transaction.
#
# Reuses the ZFS Module Guard's zfs.ko-presence check (lib/zfs/verify.sh) so
# there is one implementation of "does this kernel have a ZFS module?".
# Sourced lib-only by tests (STRAY_KERNEL_LIB_ONLY=1) to skip the runtime.
# =============================================================================

# Source the ZFS Module Guard helpers (provides zfs_kernels_missing_module).
# In the repo it sits at ../zfs/verify.sh; once installed to
# /usr/local/lib/archzfs/ it is staged as a sibling.
_STRAY_VERIFY_SH="${BASH_SOURCE[0]%/*}/../zfs/verify.sh"
[[ -f "$_STRAY_VERIFY_SH" ]] || _STRAY_VERIFY_SH="${BASH_SOURCE[0]%/*}/verify.sh"
# shellcheck source=../zfs/verify.sh
source "$_STRAY_VERIFY_SH"

# Pure: print the pkgbase of every installed kernel (from
# <modules_dir>/*/pkgbase markers) that is NOT in the selected set (the
# remaining args) — the Stray Kernels — one per line, sorted-unique.
stray_kernels() {
  local modules_dir="$1"
  shift
  local -A selected=()
  local s
  for s in "$@"; do selected["$s"]=1; done
  local marker base
  for marker in "$modules_dir"/*/pkgbase; do
    [[ -f "$marker" ]] || continue
    base="$(<"$marker")"
    [[ -n "${selected[$base]:-}" ]] || printf '%s\n' "$base"
  done | sort -u
}

# Warn (stderr) for each Stray Kernel and each kernel missing zfs.ko over
# <modules_dir>, given the selected package bases. Never removes a kernel and
# always returns 0 — it only informs.
stray_kernel_warn() {
  local modules_dir="$1"
  shift
  local k
  while IFS= read -r k; do
    [[ -n "$k" ]] && echo "WARNING: Stray Kernel '$k' is installed but not in" \
      "Kernel Selection — it wastes /boot space and never reaches the ESP." >&2
  done < <(stray_kernels "$modules_dir" "$@")
  while IFS= read -r k; do
    [[ -n "$k" ]] && echo "WARNING: kernel '$k' has no zfs.ko — it could not" \
      "import the ZFS root if it were booted." >&2
  done < <(zfs_kernels_missing_module "$modules_dir")
  return 0
}

# Lib-only sourcing for tests: skip the runtime below.
[[ "${STRAY_KERNEL_LIB_ONLY:-0}" == "1" ]] && return 0

# Runtime (warn hook): read the persisted selected package bases and warn over
# the installed kernels. Never fails the transaction.
_stray_kernel_run() {
  local selected=() list=/usr/local/lib/archzfs/selected-kernels
  [[ -f "$list" ]] && mapfile -t selected <"$list"
  stray_kernel_warn /usr/lib/modules "${selected[@]+"${selected[@]}"}"
}

[[ "${1:-}" == "warn" ]] && _stray_kernel_run
