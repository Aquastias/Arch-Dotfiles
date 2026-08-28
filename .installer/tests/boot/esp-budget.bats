#!/usr/bin/env bats
# Tests for .os/lib/boot/esp-budget.sh — the pre-install ESP budget model
# (ADR 0078). Pure arithmetic: estimate how much ESP an ESP-mirroring loader
# needs to hold every selected kernel's images (grub is exempt — it reads /boot
# natively), size it upward-only from the 2G floor, and check a pinned esp_size.

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/boot/esp-budget.sh"
}

# ── need estimate ────────────────────────────────────────────────────────────

@test "esp_budget_need_mib: grub is exempt (tiny fixed ESP)" {
  [ "$(esp_budget_need_mib 4 zfs grub)" -eq 512 ]
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

@test "esp_budget_auto_size: four ZFS kernels land at the 2G floor" {
  [ "$(esp_budget_auto_size 4 zfs systemd-boot)" = "2G" ]
}

@test "esp_budget_auto_size: five ZFS kernels grow the ESP above 2G" {
  # need 2215 → round up to 2304 MiB
  [ "$(esp_budget_auto_size 5 zfs systemd-boot)" = "2304M" ]
}

@test "esp_budget_auto_size: grub takes the fixed small ESP" {
  [ "$(esp_budget_auto_size 5 zfs grub)" = "512M" ]
}

@test "esp_budget_auto_size: efistub/limine/refind size like systemd-boot" {
  [ "$(esp_budget_auto_size 5 zfs efistub)" = "2304M" ]
  [ "$(esp_budget_auto_size 5 zfs limine)"  = "2304M" ]
  [ "$(esp_budget_auto_size 5 zfs refind)"  = "2304M" ]
}

# ── fits guard ───────────────────────────────────────────────────────────────

@test "esp_budget_fits_mib: a 1G pin cannot hold 4 ZFS kernels" {
  ! esp_budget_fits_mib 1024 4 zfs systemd-boot
}

@test "esp_budget_fits_mib: 2G holds 4 ZFS kernels" {
  esp_budget_fits_mib 2048 4 zfs systemd-boot
}

@test "esp_budget_fits_mib: grub is always exempt (tiny ESP passes)" {
  esp_budget_fits_mib 256 5 zfs grub
}

# ── fits by size string (the Guided live check) ──────────────────────────────

@test "esp_budget_size_mib: parses G / M / bare" {
  [ "$(esp_budget_size_mib 2G)"   -eq 2048 ]
  [ "$(esp_budget_size_mib 512M)" -eq 512 ]
  [ "$(esp_budget_size_mib 800)"  -eq 800 ]
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
