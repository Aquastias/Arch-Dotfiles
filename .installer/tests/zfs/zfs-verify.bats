#!/usr/bin/env bats
# Tests for .os/lib/zfs/verify.sh — fail-fast ZFS Module Guard (ADR 0024).
#
# The guard runs host-side after pacstrap and before chroot configuration: it
# verifies a loadable `zfs` module exists for every kernel installed into the
# target, aborting early (instead of a mid-`mkinitcpio` crash) when archzfs
# could not build ZFS against a selected kernel. See ADR 0024.
#
# Strategy (mirrors zfs-module.bats): build a temp module tree with `pkgbase`
# markers and optional `zfs.ko*` files; the pure helper reports which kernels
# lack a module. No real /usr/lib/modules, no DKMS, no modinfo.

setup() {
  TEST_DIR="$(mktemp -d)"
  MODULES="$TEST_DIR/modules"
  mkdir -p "$MODULES"

  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../../lib/zfs/verify.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# Create a kernel dir with a pkgbase marker and, optionally, a built zfs module.
#   _kernel <kver> <pkgbase> <has_module:0|1>
_kernel() {
  local kver="$1" pkgbase="$2" has="$3"
  mkdir -p "$MODULES/$kver"
  echo "$pkgbase" > "$MODULES/$kver/pkgbase"
  if [[ "$has" == 1 ]]; then
    mkdir -p "$MODULES/$kver/updates/dkms"
    : > "$MODULES/$kver/updates/dkms/zfs.ko.zst"
  fi
}

@test "all kernels have a zfs module → empty missing-set" {
  _kernel 6.12.1-lts      linux-lts 1
  _kernel 7.0.10-arch1-1  linux     1

  run zfs_kernels_missing_module "$MODULES"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a kernel lacking the module → its pkgbase flavour returned" {
  _kernel 6.12.1-lts      linux-lts 1
  _kernel 7.0.10-arch1-1  linux     0   # archzfs has no build for rolling

  run zfs_kernels_missing_module "$MODULES"
  [ "$status" -eq 0 ]
  [ "$output" = "linux" ]
}

@test "dirs without a pkgbase marker are not counted as kernels" {
  _kernel 6.12.1-lts linux-lts 1
  # An extramodules dir has no pkgbase and no zfs.ko — must NOT be flagged.
  mkdir -p "$MODULES/extramodules-6.12-lts"

  run zfs_kernels_missing_module "$MODULES"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "guard aborts naming the kernel + archzfs when a module is missing" {
  local root="$TEST_DIR/mnt"
  MODULES="$root/usr/lib/modules"
  mkdir -p "$MODULES"
  _kernel 7.0.10-arch1-1 linux 0

  run zfs_verify_target_modules "$root"
  [ "$status" -ne 0 ]
  [[ "$output" == *"linux"* ]]
  [[ "$output" == *"archzfs"* ]]
}

@test "guard passes silently when every kernel has a module (lts path)" {
  local root="$TEST_DIR/mnt"
  MODULES="$root/usr/lib/modules"
  mkdir -p "$MODULES"
  _kernel 6.12.1-lts linux-lts 1

  run zfs_verify_target_modules "$root"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
