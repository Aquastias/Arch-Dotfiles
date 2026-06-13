#!/usr/bin/env bats
# Tests for lib/boot/stray-kernel.sh — the Stray Kernel detector.
#
# Sourced lib-only (STRAY_KERNEL_LIB_ONLY=1) so the warn-hook runtime is
# skipped. The detector reuses the ZFS Module Guard's zfs.ko-presence check
# (lib/zfs/verify.sh) over a fixture module tree of pkgbase markers.

setup() {
  STRAY_KERNEL_LIB_ONLY=1
  error() {
    echo "ERROR: $*" >&2
    exit 1
  }
  # shellcheck source=../../lib/boot/stray-kernel.sh
  source "$BATS_TEST_DIRNAME/../../lib/boot/stray-kernel.sh"
  MODULES="$(mktemp -d)"
}

teardown() { rm -rf "$MODULES"; }

# _kernel <version-dir> <pkgbase> [zfs]  — fake an installed kernel module tree
_kernel() {
  mkdir -p "$MODULES/$1"
  printf '%s\n' "$2" >"$MODULES/$1/pkgbase"
  if [[ "${3:-}" == zfs ]]; then
    mkdir -p "$MODULES/$1/updates/dkms"
    : >"$MODULES/$1/updates/dkms/zfs.ko"
  fi
}

@test "stray_kernels reports installed kernels not in the selected set" {
  _kernel 6.18.35-1-lts linux-lts zfs
  _kernel 7.0.11-arch1-1 linux zfs
  run stray_kernels "$MODULES" linux-lts
  [ "$status" -eq 0 ]
  grep -qxF linux <<<"$output"
  ! grep -qxF linux-lts <<<"$output"
}

@test "stray_kernel_warn warns on stray + zfs.ko-less kernels, never fails" {
  _kernel 6.18.35-1-lts linux-lts zfs
  _kernel 7.0.11-arch1-1 linux # stray AND no zfs.ko
  run stray_kernel_warn "$MODULES" linux-lts
  [ "$status" -eq 0 ] # never fails the transaction
  [[ "$output" == *"Stray Kernel"* ]]
  [[ "$output" == *"linux"* ]]
  [[ "$output" == *"zfs.ko"* ]]
}
