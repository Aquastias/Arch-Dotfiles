#!/usr/bin/env bats
# esp_stage_kernel (lib/boot/esp-stage.sh, ADR 0078): copy a kernel's images
# onto the ESP and print ONLY the fallback image name, which callers capture
# into a loader entry.

bats_require_minimum_version 1.5.0

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/boot/esp-stage.sh"
  BOOT="$BATS_TEST_TMPDIR/boot"; ESP="$BATS_TEST_TMPDIR/esp"
  mkdir -p "$BOOT" "$ESP"
  touch "$BOOT/vmlinuz-linux-lts" "$BOOT/initramfs-linux-lts.img"
  export ESP_STAGE_BOOT_DIR="$BOOT"
}

@test "prints only the fallback name when it generates the image" {
  # Regression (Audit Run 20260929): mkinitcpio's stdout leaked into the
  # captured name, so fallback entries carried '==>' / '->' lines.
  mkinitcpio() {
    printf '==> Building image from preset\n  -> -k /boot/vmlinuz\n'
    touch "$BOOT/initramfs-linux-lts-fallback.img"
  }
  run --separate-stderr esp_stage_kernel linux-lts "$ESP"
  [ "$status" -eq 0 ]
  [ "$output" = "initramfs-linux-lts-fallback.img" ]
  [ -f "$ESP/initramfs-linux-lts-fallback.img" ]
  [ -f "$ESP/vmlinuz-linux-lts" ]
}

@test "prints nothing when no fallback image can be built" {
  mkinitcpio() { echo '==> ERROR: nope'; return 1; }
  run --separate-stderr esp_stage_kernel linux-lts "$ESP"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
