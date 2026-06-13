#!/usr/bin/env bats
# Tests for tools/harden-boot.sh — boot-resilience retrofit (ADR 0038).
#
# Sourced lib-only (HARDEN_BOOT_LIB_ONLY=1) so the pure planner helpers are
# exercised without the apply/runtime (which mutates a running system).

setup() {
  HARDEN_BOOT_LIB_ONLY=1
  # shellcheck source=../tools/harden-boot.sh
  source "$BATS_TEST_DIRNAME/../tools/harden-boot.sh"
  ROOT="$(mktemp -d)"
}

teardown() { rm -rf "$ROOT"; }

@test "detect_bootloader: systemd-boot when loader/entries exists" {
  mkdir -p "$ROOT/boot/efi/loader/entries"
  run harden_boot_detect_bootloader "$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "systemd-boot" ]
}

@test "detect_bootloader: grub when /boot/grub exists" {
  mkdir -p "$ROOT/boot/grub"
  run harden_boot_detect_bootloader "$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "grub" ]
}

@test "should_drop_fallback: true below 1G, false at/above" {
  run harden_boot_should_drop_fallback 512
  [ "$status" -eq 0 ]
  run harden_boot_should_drop_fallback 1024
  [ "$status" -ne 0 ]
  run harden_boot_should_drop_fallback 2048
  [ "$status" -ne 0 ]
}

@test "plan: systemd-boot includes sync+warn+microcode, drops fallback small ESP" {
  run harden_boot_plan systemd-boot 512
  [ "$status" -eq 0 ]
  [[ "$output" == *install-esp-kernel-sync* ]]
  [[ "$output" == *install-warn-hook* ]]
  [[ "$output" == *reconcile-microcode* ]]
  [[ "$output" == *drop-fallback* ]]
}

@test "plan: systemd-boot on a 2G ESP keeps the fallback" {
  run harden_boot_plan systemd-boot 2048
  [ "$status" -eq 0 ]
  [[ "$output" != *drop-fallback* ]]
}

@test "plan: grub pins default + installs warn hook, no esp-sync" {
  run harden_boot_plan grub 2048
  [ "$status" -eq 0 ]
  [[ "$output" == *pin-grub-default* ]]
  [[ "$output" == *install-warn-hook* ]]
  [[ "$output" != *install-esp-kernel-sync* ]]
}
