#!/usr/bin/env bats
# Tests for .installer/lib/boot/bootloaders.sh — the Bootloader Manifest (ADR
# 0077).
# Pure token table: options.bootloader value → EFI loader path, package set,
# ESP-entry style, and whether the loader boots from the FAT ESP (ESP-mirroring)
# or reads /boot natively (grub). Sourced host-side (package resolver / list)
# and staged into the chroot for the orchestrator's secondary-ESP registration.

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/boot/bootloaders.sh"
}

# ── EFI loader path ──────────────────────────────────────────────────────────

@test "bootloader_efi_loader: systemd-boot" {
  local want='\EFI\systemd\systemd-bootx64.efi'
  [ "$(bootloader_efi_loader systemd-boot)" = "$want" ]
}

@test "bootloader_efi_loader: grub" {
  [ "$(bootloader_efi_loader grub)" = '\EFI\GRUB\grubx64.efi' ]
}

@test "bootloader_efi_loader: limine and refind" {
  [ "$(bootloader_efi_loader limine)" = '\EFI\limine\limine_x64.efi' ]
  [ "$(bootloader_efi_loader refind)" = '\EFI\refind\refind_x64.efi' ]
}

@test "bootloader_efi_loader: efistub has no static loader path (empty)" {
  [ -z "$(bootloader_efi_loader efistub)" ]
}

@test "bootloader_efi_loader: unknown loader aborts" {
  run bootloader_efi_loader frobnicate
  [ "$status" -ne 0 ]
}

# ── package set ──────────────────────────────────────────────────────────────

@test "bootloader_packages: grub adds the grub package" {
  [ "$(bootloader_packages grub)" = "grub" ]
}

@test "bootloader_packages: systemd-boot adds nothing (ships with systemd)" {
  [ -z "$(bootloader_packages systemd-boot)" ]
}

@test "bootloader_packages: limine and refind add their own package" {
  [ "$(bootloader_packages limine)" = "limine" ]
  [ "$(bootloader_packages refind)" = "refind" ]
}

@test "bootloader_packages: efistub adds nothing (efibootmgr is in base)" {
  [ -z "$(bootloader_packages efistub)" ]
}

@test "bootloader_packages: unknown loader aborts" {
  run bootloader_packages frobnicate
  [ "$status" -ne 0 ]
}

# ── ESP-entry style ──────────────────────────────────────────────────────────

@test "bootloader_esp_style: systemd-boot uses a loader binary" {
  [ "$(bootloader_esp_style systemd-boot)" = "loader-binary" ]
}

@test "bootloader_esp_style: grub uses a loader binary" {
  [ "$(bootloader_esp_style grub)" = "loader-binary" ]
}

# ── ESP-mirroring classification (ADR 0077) ──────────────────────────────────

@test "bootloader_esp_mirrors: systemd-boot mirrors kernels onto the ESP" {
  [ "$(bootloader_esp_mirrors systemd-boot)" = "yes" ]
}

@test "bootloader_esp_mirrors: grub reads /boot natively (no ESP mirror)" {
  [ "$(bootloader_esp_mirrors grub)" = "no" ]
}

@test "bootloader_esp_style: efistub has no loader binary" {
  [ "$(bootloader_esp_style efistub)" = "efistub" ]
}

@test "bootloader_esp_mirrors: efistub/limine/refind all mirror (ADR 0077)" {
  [ "$(bootloader_esp_mirrors efistub)" = "yes" ]
  [ "$(bootloader_esp_mirrors limine)" = "yes" ]
  [ "$(bootloader_esp_mirrors refind)" = "yes" ]
}

# ── validity ─────────────────────────────────────────────────────────────────

@test "bootloader_is_valid: true for known, false for unknown" {
  bootloader_is_valid systemd-boot
  bootloader_is_valid grub
  ! bootloader_is_valid frobnicate
}

# ── drift guard: the manifest's valid set == the menu enum SSOT ───────────────

@test "drift guard: manifest loaders == menu_enum_options bootloader set" {
  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"
  local enum manifest
  enum="$(menu_enum_options options.bootloader | sort)"
  manifest="$(bootloader_all | sort)"
  [ "$manifest" = "$enum" ]
}
