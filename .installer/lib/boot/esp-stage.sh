#!/usr/bin/env bash
# =============================================================================
# lib/boot/esp-stage.sh — mirror one kernel's images onto the ESP (ADR 0078)
# =============================================================================
# Sourced by bootloader-common.sh (chroot) and its tests. Stdout carries ONLY
# the fallback image name: callers capture it into a loader entry, so every
# tool's own output goes to stderr.
# =============================================================================

# esp_stage_kernel <kbase> <esp> — copy vmlinuz + default initramfs onto <esp>,
# building the fallback initramfs when the preset did not. Prints the fallback
# image name when it exists (the caller renders a fallback entry), else nothing.
esp_stage_kernel() {
  local kbase="$1" esp="$2" boot="${ESP_STAGE_BOOT_DIR:-/boot}"
  local initramfs="initramfs-${kbase}.img"
  local initramfs_fb="initramfs-${kbase}-fallback.img"
  cp "${boot}/vmlinuz-${kbase}" "$esp/"
  cp "${boot}/${initramfs}"     "$esp/"
  if [[ ! -f "${boot}/${initramfs_fb}" ]]; then
    { mkinitcpio -p "$kbase" -S autodetect \
        || mkinitcpio -g "${boot}/${initramfs_fb}"; } >&2 2>/dev/null || true
  fi
  if [[ -f "${boot}/${initramfs_fb}" ]]; then
    cp "${boot}/${initramfs_fb}" "$esp/"
    printf '%s\n' "$initramfs_fb"
  fi
}
