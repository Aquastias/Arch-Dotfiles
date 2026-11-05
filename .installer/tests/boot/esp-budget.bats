#!/usr/bin/env bats
# Tests for .installer/lib/boot/esp-budget.sh — the pre-install ESP budget model
# (ADR 0078). Pure arithmetic: estimate how much ESP an ESP-mirroring loader
# needs to hold every selected kernel's images (grub too: its kernels live on
# the ESP since 2026-10-04), size it upward-only from the 2G floor, and check
# a pinned esp_size.

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/boot/esp-budget.sh"
}

# ── need estimate ────────────────────────────────────────────────────────────

@test "esp_budget_need_mib: grub counts kernels like systemd-boot" {
  [ "$(esp_budget_need_mib 4 zfs grub)" -eq 1910 ]
}

@test "esp_budget_need_mib: four ZFS kernels ≈ 1.9G (systemd-boot)" {
  # base 180 + 4×(16+54+205+30 zfs) + transient 205 + one-kernel slack 305
  [ "$(esp_budget_need_mib 4 zfs systemd-boot)" -eq 1910 ]
}

@test "esp_budget_need_mib: ext4 drops the per-kernel zfs surcharge" {
  # base 180 + 1×275 + transient 205 + slack 275
  [ "$(esp_budget_need_mib 1 ext4 systemd-boot)" -eq 935 ]
}

# ── auto size (upward-only from 2G) ──────────────────────────────────────────

@test "esp_budget_auto_size: never below the 2G floor (one kernel)" {
  [ "$(esp_budget_auto_size 1 zfs systemd-boot)" = "2G" ]
}

@test "esp_budget_auto_size: four ZFS kernels + previous pairs grow past 2G" {
  # need 1910 + 4 x 100 previous = 2310 → round up to 2560 MiB (ADR 0166)
  [ "$(esp_budget_auto_size 4 zfs systemd-boot)" = "2560M" ]
}

@test "esp_budget_auto_size: five ZFS kernels grow the ESP above 2G" {
  # need 2215 + 5 x 100 previous = 2715 → round up to 2816 MiB
  [ "$(esp_budget_auto_size 5 zfs systemd-boot)" = "2816M" ]
}

@test "esp_budget_auto_size: grub sizes like systemd-boot" {
  [ "$(esp_budget_auto_size 5 zfs grub)" = "2816M" ]
}

@test "esp_budget_auto_size: efistub/limine/refind size like systemd-boot" {
  [ "$(esp_budget_auto_size 5 zfs efistub)" = "2816M" ]
  [ "$(esp_budget_auto_size 5 zfs limine)"  = "2816M" ]
  [ "$(esp_budget_auto_size 5 zfs refind)"  = "2816M" ]
}

# ── fits guard ───────────────────────────────────────────────────────────────

@test "esp_budget_fits_mib: a 1G pin cannot hold 4 ZFS kernels" {
  ! esp_budget_fits_mib 1024 4 zfs systemd-boot
}

@test "esp_budget_fits_mib: 2G holds 4 ZFS kernels" {
  esp_budget_fits_mib 2048 4 zfs systemd-boot
}

@test "esp_budget_fits_mib: grub is no longer exempt (tiny ESP fails)" {
  ! esp_budget_fits_mib 256 5 zfs grub
}

# ── fits by size string (the Guided live check) ──────────────────────────────

@test "esp_budget_size_mib: parses G / M / bare" {
  [ "$(esp_budget_size_mib 2G)"   -eq 2048 ]
  [ "$(esp_budget_size_mib 512M)" -eq 512 ]
  [ "$(esp_budget_size_mib 800)"  -eq 800 ]
}

@test "esp_budget_size_mib: a leading zero is decimal, not octal" {
  [ "$(esp_budget_size_mib 08G)" -eq 8192 ]
  [ "$(esp_budget_size_mib 0512M)" -eq 512 ]
}

@test "esp_budget_fits_size: auto always fits" {
  esp_budget_fits_size auto 5 zfs systemd-boot
}

@test "esp_budget_fits_size: a 1G pin fails for 4 ZFS kernels" {
  ! esp_budget_fits_size 1G 4 zfs systemd-boot
}

@test "esp_budget_fits_size: 2G pin holds 4 ZFS kernels" {
  esp_budget_fits_size 2G 4 zfs systemd-boot
}

@test "esp_budget_previous_mib: one previous pair per kernel, zfs surcharge" {
  [ "$(esp_budget_previous_mib 1 zfs)" -eq 100 ]
  [ "$(esp_budget_previous_mib 2 ext4)" -eq 140 ]
}

@test "esp_budget_fits_mib: previous pairs are optional, a 2G pin still fits" {
  # ADR 0166: a short ESP skips previous pairs; it never fails the install.
  esp_budget_fits_mib 2048 4 zfs systemd-boot
}
