#!/usr/bin/env bats
# Tests for lib/grub-common.sh — _grub_default_config (GRUB default-pin).
#
# Pins the Primary Kernel as the default top-level entry via GRUB_TOP_LEVEL so a
# higher-versioned Stray Kernel cannot become the default boot entry (ADR 0038).

setup() {
  # shellcheck source=../lib/grub-common.sh
  source "$BATS_TEST_DIRNAME/../lib/grub-common.sh"
}

@test "default config pins GRUB_TOP_LEVEL to the primary kernel, GRUB_DEFAULT=0" {
  run _grub_default_config rpool/ROOT/arch /boot/vmlinuz-linux-lts
  [ "$status" -eq 0 ]
  [[ "$output" == *'GRUB_TOP_LEVEL="/boot/vmlinuz-linux-lts"'* ]]
  [[ "$output" == *'GRUB_DEFAULT=0'* ]]
}

@test "default config preserves the ZFS root cmdline" {
  run _grub_default_config rpool/ROOT/arch /boot/vmlinuz-linux-lts
  [ "$status" -eq 0 ]
  [[ "$output" == *'root=ZFS=rpool/ROOT/arch zfs_import_dir=/dev/disk/by-id'* ]]
}

@test "empty primary kernel omits the GRUB_TOP_LEVEL pin (graceful)" {
  run _grub_default_config rpool/ROOT/arch ""
  [ "$status" -eq 0 ]
  [[ "$output" != *GRUB_TOP_LEVEL* ]]
  [[ "$output" == *GRUB_DEFAULT=0* ]]
}
