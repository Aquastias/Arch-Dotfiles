#!/usr/bin/env bats
# Tests for .installer/lib/zfs/verify.sh — fail-fast ZFS Module Guard (ADR
# 0024).
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

# ── zfs_missing_selected_kernels (pure): abort-set = missing ∩ selected ───────

@test "missing∩selected: a missing SELECTED kernel is in the abort set" {
  run zfs_missing_selected_kernels "$(printf 'linux\nlinux-lts\n')" linux-lts
  [ "$status" -eq 0 ]
  [ "$output" = "linux-lts" ]
}

@test "missing∩selected: a missing STRAY kernel is excluded" {
  # `linux` missing but only `linux-lts` is selected → not in the abort set.
  run zfs_missing_selected_kernels "$(printf 'linux\n')" linux-lts
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "missing∩selected: no selection ⇒ empty abort set" {
  run zfs_missing_selected_kernels "$(printf 'linux\nlinux-lts\n')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── guard: selection-aware abort vs stray tolerance (ADR 0138) ────────────────

@test "guard aborts when a SELECTED kernel lacks the module" {
  local root="$TEST_DIR/mnt"
  MODULES="$root/usr/lib/modules"
  mkdir -p "$MODULES"
  _kernel 7.0.10-arch1-1 linux 0

  run zfs_verify_target_modules "$root" linux
  [ "$status" -ne 0 ]
  [[ "$output" == *"linux"* ]]
  [[ "$output" == *"archzfs"* ]]
}

@test "guard TOLERATES a stray kernel lacking the module (warn, pass)" {
  local root="$TEST_DIR/mnt"
  MODULES="$root/usr/lib/modules"
  mkdir -p "$MODULES"
  _kernel 6.12.1-lts      linux-lts 1   # selected, has module
  _kernel 7.2.6-arch2-1   linux     0   # stray (wine-pulled), no module

  run zfs_verify_target_modules "$root" linux-lts
  [ "$status" -eq 0 ]                    # NOT fatal — stray tolerated
  [[ "$output" == *"Stray Kernel 'linux'"* ]]
  [[ "$output" == *"tolerated"* ]]
}

@test "guard aborts on the selected kernel even when a stray is also missing" {
  local root="$TEST_DIR/mnt"
  MODULES="$root/usr/lib/modules"
  mkdir -p "$MODULES"
  _kernel 6.12.1-lts      linux-lts 0   # selected, MISSING → fatal
  _kernel 7.2.6-arch2-1   linux     0   # stray, missing → warn only

  run zfs_verify_target_modules "$root" linux-lts
  [ "$status" -ne 0 ]
  [[ "$output" == *"linux-lts"* ]]       # named in the abort
}

# Regression: the guard must survive the installer's `set -Eeuo pipefail`. A
# trailing stray once made an internal `| sort -u` pipe fail the `$(…)` capture
# and abort the guard (the VM install died here though plain bats passed).
@test "guard tolerates a stray under set -Eeuo pipefail (no ERR-trap crash)" {
  local root="$TEST_DIR/mnt"
  local mods="$root/usr/lib/modules"
  mkdir -p "$mods/6.12.75-1-lts/updates/dkms" "$mods/7.2.6-arch2-1"
  echo linux-lts > "$mods/6.12.75-1-lts/pkgbase"
  : > "$mods/6.12.75-1-lts/updates/dkms/zfs.ko.zst"
  echo linux > "$mods/7.2.6-arch2-1/pkgbase"   # stray, no zfs.ko

  run bash -c '
    set -Eeuo pipefail
    source "'"$BATS_TEST_DIRNAME"'/../../lib/common.sh"
    source "'"$BATS_TEST_DIRNAME"'/../../lib/zfs/verify.sh"
    zfs_verify_target_modules "'"$root"'" linux-lts
    echo "GUARD_OK"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"GUARD_OK"* ]]           # reached the line after the guard
  [[ "$output" == *"Stray Kernel 'linux'"* ]]
}

@test "guard passes silently when every selected kernel has a module (lts path)" {
  local root="$TEST_DIR/mnt"
  MODULES="$root/usr/lib/modules"
  mkdir -p "$MODULES"
  _kernel 6.12.1-lts linux-lts 1

  run zfs_verify_target_modules "$root" linux-lts
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
