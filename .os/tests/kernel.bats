#!/usr/bin/env bats
# Tests for .os/lib/kernel.sh — Kernel Selection token table (ADR 0024).
# Pure mapping: flavour token → kernel package base + headers. The same table
# is used host-side (packages) and chroot-side (initramfs preset, bootloader).

setup() {
  source "$BATS_TEST_DIRNAME/../lib/kernel.sh"
}

@test "kernel_pkg: maps every flavour token to its package base" {
  [ "$(kernel_pkg lts)"      = "linux-lts" ]
  [ "$(kernel_pkg default)"  = "linux" ]
  [ "$(kernel_pkg zen)"      = "linux-zen" ]
  [ "$(kernel_pkg hardened)" = "linux-hardened" ]
}

@test "kernel_headers_pkg: appends -headers to the package base" {
  [ "$(kernel_headers_pkg lts)"      = "linux-lts-headers" ]
  [ "$(kernel_headers_pkg hardened)" = "linux-hardened-headers" ]
}

@test "kernel_is_valid_token: true for known, false for unknown" {
  kernel_is_valid_token zen
  ! kernel_is_valid_token frobnicate
}

@test "kernel_pkg: unknown token aborts" {
  run kernel_pkg frobnicate
  [ "$status" -ne 0 ]
}
