#!/usr/bin/env bats
# Tests for .installer/lib/zfs/module.sh — shared ZFS DKMS build/load.
#
# Regression guard for the 2026-05-31 install failure: the old 03-install.sh
# fallback ran `pacman -S linux-headers` UNPINNED (pulling a newer kernel's
# headers than the running ISO kernel) and never passed --kernelsourcedir, so
# DKMS built for the wrong kernel and `modprobe zfs` found nothing. See ADR
# 0023. These tests pin the corrected behaviour.
#
# Strategy: stub every external (pacman/dkms/curl/...) as a shell function that
# appends its argv to $CALLS, and inject ZFS_MODULES_DIR / ZFS_SRC_DIR temp
# dirs so the function's filesystem probes hit fixtures, not the real system.

setup() {
  TEST_DIR="$(mktemp -d)"
  CALLS="$TEST_DIR/calls.log"
  : > "$CALLS"

  export ZFS_MODULES_DIR="$TEST_DIR/modules"
  export ZFS_SRC_DIR="$TEST_DIR/src"
  mkdir -p "$ZFS_SRC_DIR/zfs-2.4.2"        # what zfs-dkms would install

  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../../lib/zfs/module.sh"

  # Stub externals — record argv, succeed by default.
  pacman()  { echo "pacman $*"  >> "$CALLS"; return 0; }
  dkms()    { echo "dkms $*"    >> "$CALLS"; return 0; }
  curl()    { echo "curl $*"    >> "$CALLS"; return 0; }
  depmod()  { echo "depmod $*"  >> "$CALLS"; return 0; }
  uname()   { case "$1" in -m) echo x86_64;; *) echo 7.0.3-arch1-1;; esac; }
  export -f pacman dkms curl depmod uname
}

teardown() { rm -rf "$TEST_DIR"; }

# Live-ISO case: the ISO ships headers for the running kernel, so the build
# must use them directly and never download/install linux-headers.
@test "zfs_install_dkms: ISO headers present → no linux-headers install" {
  mkdir -p "$ZFS_MODULES_DIR/7.0.3-arch1-1/build"   # scenario A

  run zfs_install_dkms 7.0.3-arch1-1
  [ "$status" -eq 0 ]

  # The exact regression: must NOT install linux-headers from a mirror/archive.
  ! grep -qE 'pacman .*(^| )linux(-lts|-hardened|-zen)?-headers' "$CALLS"
  ! grep -q 'curl' "$CALLS"
}

@test "zfs_install_dkms: builds against the running kernel's source tree" {
  mkdir -p "$ZFS_MODULES_DIR/7.0.3-arch1-1/build"

  run zfs_install_dkms 7.0.3-arch1-1
  [ "$status" -eq 0 ]

  # The fix: dkms build must be pinned to the running kernel AND pointed at the
  # ISO's own source tree via --kernelsourcedir.
  grep -q "dkms build -m zfs -v 2.4.2 -k 7.0.3-arch1-1" "$CALLS"
  grep -q -- "--kernelsourcedir ${ZFS_MODULES_DIR}/7.0.3-arch1-1/build" "$CALLS"
  grep -q "dkms install -m zfs -v 2.4.2 -k 7.0.3-arch1-1" "$CALLS"
}

# limine/refind 20261008: the GitHub-hosted archzfs repo blipped (a db/asset
# size mismatch) twice in a row; three refreshed tries ride it out
@test "zfs_install_dkms: a blipping archzfs fetch is retried, db refreshed" {
  mkdir -p "$ZFS_MODULES_DIR/7.0.3-arch1-1/build"
  echo 0 > "$TEST_DIR/n"
  pacman() { echo "pacman $*" >> "$CALLS"
    if [[ "$*" == "-S --noconfirm --needed dkms zfs-dkms zfs-utils" ]]; then
      local n; n=$(($(cat "$TEST_DIR/n") + 1)); echo $n > "$TEST_DIR/n"
      ((n >= 3)); return; fi; }
  sleep() { :; }
  zfs_install_dkms 7.0.3-arch1-1 >/dev/null
  [ "$(cat "$TEST_DIR/n")" -eq 3 ]
  [ "$(grep -c '^pacman -Syy --noconfirm$' "$CALLS")" -eq 2 ]
}

@test "zfs_install_dkms: the live ISO's failing initcpio hook stays quiet" {
  # 20261008 regression: 17/18 installs logged pacman's harmless hook error
  mkdir -p "$ZFS_MODULES_DIR/7.0.3-arch1-1/build"
  pacman() { [[ "$1" == -S ]] && echo "error: command failed to execute" >&2
    return 0; }
  run zfs_install_dkms 7.0.3-arch1-1
  [ "$status" -eq 0 ]
  [[ "$output" != *"command failed to execute"* ]]
}
