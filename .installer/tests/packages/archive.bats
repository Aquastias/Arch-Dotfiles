#!/usr/bin/env bats
# Tests for .installer/lib/packages/archive.sh — the shared
# archive.archlinux.org exact-version fetch (extracted from lib/zfs/module.sh).
#
# The pure helpers (archive_kernel_version_to_package_version,
# archive_package_url) are asserted directly. The side-effecting helpers stub
# pacman/curl as functions that record argv to $CALLS and succeed/fail on
# demand, so no network or real pacman is touched.

setup() {
  TEST_DIR="$(mktemp -d)"
  CALLS="$TEST_DIR/calls.log"
  : > "$CALLS"
  export TMPDIR="$TEST_DIR"

  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../../lib/packages/archive.sh"

  # Stub externals — record argv, succeed by default.
  pacman() { echo "pacman $*" >> "$CALLS"; return 0; }
  curl()   { echo "curl $*"   >> "$CALLS"; return 0; }
  export -f pacman curl
}

teardown() { rm -rf "$TEST_DIR"; }

# ── archive_kernel_version_to_package_version (pure)
# ────────────────────────────────────────────────────

@test "archive_kernel_version_to_package_version: the hyphen before arch becomes a dot" {
  run archive_kernel_version_to_package_version "6.19.10-arch1-1"
  [ "$status" -eq 0 ]
  [ "$output" = "6.19.10.arch1-1" ]
}

@test "archive_kernel_version_to_package_version: lts release string" {
  run archive_kernel_version_to_package_version "6.12.48-1-lts"
  [ "$status" -eq 0 ]
  # -lts kernels carry no -archN token, so the string is unchanged.
  [ "$output" = "6.12.48-1-lts" ]
}

# ── archive_package_url (pure)
# ───────────────────────────────────────────────────

@test "archive_package_url: first-letter subdir + versioned filename" {
  run archive_package_url "linux-lts-headers" "6.12.48.arch1-1"
  [ "$status" -eq 0 ]
  [ "$output" = "https://archive.archlinux.org/packages/l/linux-lts-headers/linux-lts-headers-6.12.48.arch1-1-x86_64.pkg.tar.zst" ]
}

@test "archive_package_url: arch override is honoured" {
  run archive_package_url "linux-lts" "6.12.48.arch1-1" "aarch64"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-6.12.48.arch1-1-aarch64.pkg.tar.zst" ]]
}

# ── archive_ensure_package_version: mirror first
# ─────────────────────────────────────────

@test "archive_ensure_package_version: mirror hit → no archive fetch" {
  run archive_ensure_package_version "linux-lts" "6.12.48.arch1-1"
  [ "$status" -eq 0 ]
  grep -q "pacman -S --noconfirm --needed linux-lts=6.12.48.arch1-1" "$CALLS"
  ! grep -q "curl" "$CALLS"
  ! grep -q "pacman -U" "$CALLS"
}

# ── archive_ensure_package_version: archive fallback
# ─────────────────────────────────────

@test "archive_ensure_package_version: mirror miss → archive download + pacman -U" {
  # Mirror -S fails; archive curl + -U succeed.
  pacman() {
    echo "pacman $*" >> "$CALLS"
    [[ "$1 $2" == "-S --noconfirm" ]] && return 1
    return 0
  }
  export -f pacman

  run archive_ensure_package_version "linux-lts" "6.12.48.arch1-1"
  [ "$status" -eq 0 ]
  grep -q "curl .*archive.archlinux.org/packages/l/linux-lts/" "$CALLS"
  grep -q "pacman -U --noconfirm" "$CALLS"
}

@test "archive_ensure_package_version: mirror miss + archive download fail → non-zero" {
  pacman() { echo "pacman $*" >> "$CALLS"; [[ "$1" == "-S" ]] && return 1; return 0; }
  curl()   { echo "curl $*"   >> "$CALLS"; return 1; }
  export -f pacman curl

  run archive_ensure_package_version "linux-lts" "6.12.48.arch1-1"
  [ "$status" -ne 0 ]
  ! grep -q "pacman -U" "$CALLS"
}
