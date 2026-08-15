#!/usr/bin/env bash
# =============================================================================
# lib/boot/bootloaders.sh — Bootloader Manifest (ADR 0077)
# =============================================================================
# The single source of truth for per-loader metadata, replacing the hardcoded
# `if grub/else systemd` chains that used to live in configure.sh (secondary-ESP
# loader path), resolver.sh, and list.sh (bootloader packages). Adding a loader
# is one row group here plus its Bootloader Adapter — no branch grows.
#
# Pure: name-in / string-out, no disk or state access. Sourced host-side by the
# package resolver and package list, and staged into the chroot for the
# orchestrator's secondary-ESP registration.
#
# Public API (each aborts on an unknown loader, except *_is_valid / *_all):
#   bootloader_efi_loader  <name> → the \EFI\...\*.efi path for the UEFI entry
#   bootloader_packages    <name> → extra package(s), one per line (maybe empty)
#   bootloader_esp_style   <name> → loader-binary | efistub (secondary-ESP kind)
#   bootloader_esp_mirrors <name> → yes | no  (boots from the FAT ESP vs native)
#   bootloader_is_valid    <name> → rc 0 if known, rc 1 otherwise
#   bootloader_all                → every known loader, one per line
#
# The `menu_enum_options options.bootloader` list is the Guided-menu SSOT; a
# drift-guard test pins bootloader_all to it so the two can never diverge.
# =============================================================================

# bootloader_all — every loader the manifest knows, one per line.
bootloader_all() {
  printf '%s\n' systemd-boot grub efistub limine refind
}

# bootloader_is_valid <name> — rc 0 when the loader is known, rc 1 otherwise.
bootloader_is_valid() {
  local name="$1" l
  while IFS= read -r l; do [[ "$l" == "$name" ]] && return 0; done \
    < <(bootloader_all)
  return 1
}

# bootloader_efi_loader <name> — the ESP-relative loader path registered as the
# UEFI boot entry (efibootmgr --loader), backslash-separated as firmware wants.
# efistub has no loader binary — it registers a per-kernel efibootmgr entry
# pointing at the kernel itself (esp_style=efistub), so it has no single path;
# it emits nothing here and callers branch on esp_style instead.
bootloader_efi_loader() {
  case "$1" in
  systemd-boot) printf '%s\n' '\EFI\systemd\systemd-bootx64.efi' ;;
  grub)         printf '%s\n' '\EFI\GRUB\grubx64.efi' ;;
  limine)       printf '%s\n' '\EFI\limine\limine_x64.efi' ;;
  refind)       printf '%s\n' '\EFI\refind\refind_x64.efi' ;;
  efistub)      : ;;
  *) _bootloader_unknown efi_loader "$1"; return 1 ;;
  esac
}

# bootloader_packages <name> — extra repo package(s) the loader needs, one per
# line. systemd-boot ships with systemd (already in base), so it emits nothing;
# grub adds grub.
bootloader_packages() {
  case "$1" in
  systemd-boot) : ;;
  efistub)      : ;;
  grub)         printf '%s\n' grub ;;
  limine)       printf '%s\n' limine ;;
  refind)       printf '%s\n' refind ;;
  *) _bootloader_unknown packages "$1"; return 1 ;;
  esac
}

# bootloader_esp_style <name> — how the secondary-ESP UEFI entry is registered.
# `loader-binary`: a self-contained loader .efi finds its own config on each ESP
# (systemd-boot, grub, limine, refind). `efistub`: no loader binary — the entry
# points at the kernel and carries initrd + cmdline load-options (ADR 0078).
bootloader_esp_style() {
  case "$1" in
  systemd-boot) printf '%s\n' loader-binary ;;
  grub)         printf '%s\n' loader-binary ;;
  limine)       printf '%s\n' loader-binary ;;
  refind)       printf '%s\n' loader-binary ;;
  efistub)      printf '%s\n' efistub ;;
  *) _bootloader_unknown esp_style "$1"; return 1 ;;
  esac
}

# bootloader_esp_mirrors <name> — `yes` for an ESP-mirroring loader (boots the
# kernel the ESP Kernel Sync copies onto the FAT ESP; counts toward the ESP
# budget), `no` for grub (reads /boot natively, tiny ESP) (ADR 0077/0078).
bootloader_esp_mirrors() {
  case "$1" in
  systemd-boot) printf '%s\n' yes ;;
  efistub)      printf '%s\n' yes ;;
  limine)       printf '%s\n' yes ;;
  refind)       printf '%s\n' yes ;;
  grub)         printf '%s\n' no ;;
  *) _bootloader_unknown esp_mirrors "$1"; return 1 ;;
  esac
}

# Internal: uniform abort for an unknown loader, naming the query.
_bootloader_unknown() {
  local what="$1" name="$2"
  printf 'bootloader_%s: unknown bootloader %s\n' "$what" "$name" >&2
}
