#!/usr/bin/env bats
# Tests for tools/harden-boot.sh — boot-resilience retrofit (ADR 0038).
#
# Sourced lib-only (HARDEN_BOOT_LIB_ONLY=1) so the pure planner helpers are
# exercised without the apply/runtime (which mutates a running system).

load lib/text-helpers

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

@test "detect_bootloader: grub-native when only the ZFS /boot/grub exists" {
  mkdir -p "$ROOT/boot/grub"
  run harden_boot_detect_bootloader "$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "grub-native" ]
}

@test "detect_bootloader: grub when its config is on the ESP" {
  mkdir -p "$ROOT/boot/efi/grub"
  : > "$ROOT/boot/efi/grub/grub.cfg"
  run harden_boot_detect_bootloader "$ROOT"
  [ "$output" = "grub" ]
}

@test "detect_bootloader: limine when limine.conf is on the ESP" {
  mkdir -p "$ROOT/boot/efi"
  : > "$ROOT/boot/efi/limine.conf"
  run harden_boot_detect_bootloader "$ROOT"
  [ "$output" = "limine" ]
}

@test "detect_bootloader: refind when refind.conf is on the ESP" {
  mkdir -p "$ROOT/boot/efi/EFI/refind"
  : > "$ROOT/boot/efi/EFI/refind/refind.conf"
  run harden_boot_detect_bootloader "$ROOT"
  [ "$output" = "refind" ]
}

@test "detect_bootloader: efistub when only kernels sit on the ESP" {
  mkdir -p "$ROOT/boot/efi"
  : > "$ROOT/boot/efi/vmlinuz-linux-lts"
  run harden_boot_detect_bootloader "$ROOT"
  [ "$output" = "efistub" ]
}

@test "detect_bootloader: empty when nothing is recognised" {
  mkdir -p "$ROOT/boot/efi"
  run harden_boot_detect_bootloader "$ROOT"
  [ -z "$output" ]
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

@test "plan: grub-native pins default + installs warn hook, no esp-sync" {
  run harden_boot_plan grub-native 2048
  [ "$status" -eq 0 ]
  [[ "$output" == *pin-grub-default* ]]
  [[ "$output" == *install-warn-hook* ]]
  [[ "$output" != *install-esp-kernel-sync* ]]
}

@test "plan: every ESP-only loader gets the ESP Kernel Sync + warn hook" {
  local loader
  for loader in grub limine refind efistub; do
    run harden_boot_plan "$loader" 512
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\n' install-esp-kernel-sync install-warn-hook \
      install-boot-recovery install-resnapshot-hook)" ]
  done
}

@test "apply: limine root writes the sync hooks and its staged kernel" {
  mkdir -p "$ROOT/boot/efi"
  : > "$ROOT/boot/efi/limine.conf"
  : > "$ROOT/boot/efi/vmlinuz-linux-lts"
  run bash "$BATS_TEST_DIRNAME/../tools/harden-boot.sh" --root "$ROOT"
  [ "$status" -eq 0 ]
  [ -f "$ROOT/etc/pacman.d/hooks/94-esp-kernel-sync.hook" ]
  grep -q "esp-kernel-sync.sh previous" \
    "$ROOT/etc/pacman.d/hooks/03-esp-previous-pair.hook"
  [ -f "$ROOT/etc/pacman.d/hooks/97-stray-kernel-warn.hook" ]
  [ "$(cat "$ROOT/usr/local/lib/archzfs/selected-kernels")" = linux-lts ]
}

@test "apply: dry-run lists actions and writes nothing" {
  mkdir -p "$ROOT/boot/efi"
  : > "$ROOT/boot/efi/vmlinuz-linux-lts"
  run bash "$BATS_TEST_DIRNAME/../tools/harden-boot.sh" --root "$ROOT" \
    --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"bootloader=efistub"* ]]
  [[ "$output" == *"would: install-esp-kernel-sync"* ]]
  [ ! -e "$ROOT/etc" ]
}

@test "apply: unknown loader exits non-zero and writes nothing" {
  mkdir -p "$ROOT/boot/efi"
  run bash "$BATS_TEST_DIRNAME/../tools/harden-boot.sh" --root "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not detect a bootloader"* ]]
  [ ! -e "$ROOT/etc" ]
}

@test "apply: a second run leaves the same hooks (idempotent)" {
  mkdir -p "$ROOT/boot/efi"
  : > "$ROOT/boot/efi/vmlinuz-linux-lts"
  bash "$BATS_TEST_DIRNAME/../tools/harden-boot.sh" --root "$ROOT"
  local first
  first="$(cat "$ROOT"/etc/pacman.d/hooks/*.hook)"
  run bash "$BATS_TEST_DIRNAME/../tools/harden-boot.sh" --root "$ROOT"
  [ "$status" -eq 0 ]
  [ "$(cat "$ROOT"/etc/pacman.d/hooks/*.hook)" = "$first" ]
}

@test "plan: systemd-boot and grub-native also get the boot recovery set" {
  run harden_boot_plan systemd-boot 2048
  [[ "$output" == *install-boot-recovery* ]]
  run harden_boot_plan grub-native 2048
  [[ "$output" == *install-boot-recovery* ]]
}

@test "apply: battery, Module Stash and Stash Restore are installed" {
  mkdir -p "$ROOT/boot/efi"
  : > "$ROOT/boot/efi/vmlinuz-linux-lts"
  run bash "$BATS_TEST_DIRNAME/../tools/harden-boot.sh" --root "$ROOT"
  [ "$status" -eq 0 ]
  grep -q 'boot-recovery.sh battery' \
    "$ROOT/etc/pacman.d/hooks/00-battery-preflight.hook"
  [ -x "$ROOT/usr/local/lib/archzfs/boot-recovery.sh" ]
  [ -f "$ROOT/etc/pacman.d/hooks/05-module-stash.hook" ]
  local wants="$ROOT/usr/lib/systemd/system/sysinit.target.wants"
  [ -L "$wants/boot-recovery-restore.service" ]
}

@test "plan: a ZFS root also gets the Update Snapshot, others do not" {
  run harden_boot_plan efistub 2048 zfs
  [[ "$output" == *install-update-snapshot* ]]
  run harden_boot_plan efistub 2048 ext4
  [[ "$output" != *install-update-snapshot* ]]
}

@test "apply: Update Snapshot hooks + resnapshot patch on a ZFS root" {
  mkdir -p "$ROOT/boot/efi" "$ROOT/usr/lib/impermanence"
  : > "$ROOT/boot/efi/vmlinuz-linux-lts"
  printf '%s\n' '#!/usr/bin/env bash' 'datasets="rpool/ROOT/etc"' \
    'for ds in $datasets; do' '  zfs destroy "${ds}@blank"' 'done' \
    > "$ROOT/usr/lib/impermanence/resnapshot.sh"
  HARDEN_BOOT_ROOT_FSTYPE=zfs run bash \
    "$BATS_TEST_DIRNAME/../tools/harden-boot.sh" --root "$ROOT"
  [ "$status" -eq 0 ]
  grep -q "update-snapshot.sh pre" \
    "$ROOT/etc/pacman.d/hooks/02-update-snapshot.hook"
  grep -q "update-snapshot.sh post" \
    "$ROOT/etc/pacman.d/hooks/zzz-update-snapshot-done.hook"
  [ -x "$ROOT/usr/local/lib/archzfs/update-snapshot.sh" ]
  local helper="$ROOT/usr/lib/impermanence/resnapshot.sh"
  [ "$(first_line_matching "$helper" 'keep-blank')" -lt \
    "$(first_line_matching "$helper" 'zfs destroy')" ]
  # idempotent: a second run does not insert the line twice
  HARDEN_BOOT_ROOT_FSTYPE=zfs bash \
    "$BATS_TEST_DIRNAME/../tools/harden-boot.sh" --root "$ROOT"
  [ "$(grep -c keep-blank "$helper")" -eq 1 ]
}

@test "plan: Undo Last Update on a ZFS root with an ESP-mirroring loader" {
  run harden_boot_plan limine 2048 zfs
  [[ "$output" == *install-undo-entry* ]]
  run harden_boot_plan grub-native 2048 zfs
  [[ "$output" != *install-undo-entry* ]]
  run harden_boot_plan limine 2048 ext4
  [[ "$output" != *install-undo-entry* ]]
}

@test "apply: Undo entry from the running cmdline + undo-update in HOOKS" {
  mkdir -p "$ROOT/boot/efi" "$ROOT/etc"
  : > "$ROOT/boot/efi/limine.conf"
  : > "$ROOT/boot/efi/vmlinuz-linux-lts"
  : > "$ROOT/boot/efi/amd-ucode.img"
  echo "HOOKS=(base udev block zfs filesystems)" > "$ROOT/etc/mkinitcpio.conf"
  local i
  for i in 1 2; do
    HARDEN_BOOT_ROOT_FSTYPE=zfs \
    HARDEN_BOOT_CMDLINE='initrd=\amd-ucode.img root=ZFS=rpool/ROOT/arch rw' \
      run bash "$BATS_TEST_DIRNAME/../tools/harden-boot.sh" --root "$ROOT"
    [ "$status" -eq 0 ]
  done
  local template="$ROOT/usr/local/lib/archzfs/undo-entry.template"
  grep -q "cmdline: root=ZFS=rpool/ROOT/arch rw undo_last_update" "$template"
  grep -q "module_path: boot():/amd-ucode.img" "$template"
  ! grep -q "initrd=" "$template"
  [ "$(cat "$ROOT/etc/mkinitcpio.conf")" \
    = "HOOKS=(base udev block zfs undo-update filesystems)" ]
}

@test "undo_cmdline: drops loader-added initrd=/BOOT_IMAGE= and the undo flag" {
  run harden_boot_undo_cmdline \
    'BOOT_IMAGE=/vmlinuz initrd=\x.img root=ZFS=a rw undo_last_update quiet'
  [ "$output" = "root=ZFS=a rw quiet" ]
}

@test "impermanence_datasets: the Rollback Datasets of the resnapshot helper" {
  printf '%s\n' '#!/usr/bin/env bash' \
    'datasets="rpool/ROOT/etc rpool/ROOT/opt"' 'for ds in $datasets; do' \
    > "$ROOT/resnapshot.sh"
  run harden_boot_impermanence_datasets "$ROOT/resnapshot.sh"
  [ "$output" = $'rpool/ROOT/etc\nrpool/ROOT/opt' ]
  run harden_boot_impermanence_datasets "$ROOT/missing.sh"
  [ -z "$output" ]
}

@test "apply: previous kernels never count as selected kernels" {
  mkdir -p "$ROOT/boot/efi/EFI/refind"
  echo "timeout 5" > "$ROOT/boot/efi/EFI/refind/refind.conf"
  : > "$ROOT/boot/efi/vmlinuz-linux-lts"
  : > "$ROOT/boot/efi/vmlinuz-linux-lts-prev"
  local i
  for i in 1 2; do
    HARDEN_BOOT_ROOT_FSTYPE=zfs HARDEN_BOOT_CMDLINE='root=x rw' \
      run bash "$BATS_TEST_DIRNAME/../tools/harden-boot.sh" --root "$ROOT"
    [ "$status" -eq 0 ]
  done
  [ "$(cat "$ROOT/usr/local/lib/archzfs/selected-kernels")" = linux-lts ]
  ! grep -q "prev-prev" "$ROOT/boot/efi/EFI/refind/refind.conf"
  [ "$(grep -c '^dont_scan_files' "$ROOT/boot/efi/EFI/refind/refind.conf")" \
    -eq 1 ]
}

@test "apply: restores a missing impermanence resnapshot hook, any fs" {
  mkdir -p "$ROOT/boot/efi" "$ROOT/usr/lib/impermanence"
  : > "$ROOT/boot/efi/vmlinuz-linux-lts"
  printf '#!/usr/bin/env bash\n' > "$ROOT/usr/lib/impermanence/resnapshot.sh"
  HARDEN_BOOT_ROOT_FSTYPE=btrfs run bash \
    "$BATS_TEST_DIRNAME/../tools/harden-boot.sh" --root "$ROOT"
  [ "$status" -eq 0 ]
  grep -q "Exec = /usr/lib/impermanence/resnapshot.sh" \
    "$ROOT/etc/pacman.d/hooks/zz-impermanence-resnapshot.hook"
}

@test "plan: every loader checks for the impermanence resnapshot hook" {
  run harden_boot_plan efistub 2048 ext4
  [[ "$output" == *install-resnapshot-hook* ]]
}

# Regression (harden-boot-warn-hook-abort): a systemd-boot root without
# /etc/default/grub used to abort after "applying: install-warn-hook".
@test "apply: systemd-boot root without grub defaults writes every hook" {
  mkdir -p "$ROOT/boot/efi/loader/entries"
  printf 'title Arch\nlinux /vmlinuz-linux-lts\ninitrd /amd-ucode.img\n' \
    > "$ROOT/boot/efi/loader/entries/arch.conf"
  printf 'title fb\nlinux /vmlinuz-linux-lts\ninitrd /x-fallback.img\n' \
    > "$ROOT/boot/efi/loader/entries/zz-fallback.conf"
  printf 'title Undo\nlinux /vmlinuz-linux-lts-prev\n' \
    > "$ROOT/boot/efi/loader/entries/arch-undo.conf"
  run bash "$BATS_TEST_DIRNAME/../tools/harden-boot.sh" --root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"harden-boot: done."* ]]
  local hooks="$ROOT/etc/pacman.d/hooks"
  [ -f "$hooks/01-esp-kernel-sync-preflight.hook" ]
  [ -f "$hooks/94-esp-kernel-sync.hook" ]
  [ -f "$hooks/97-stray-kernel-warn.hook" ]
  [ "$(cat "$ROOT/usr/local/lib/archzfs/selected-kernels")" = linux-lts ]
  # reconcile-microcode dropped the initrd for the absent ucode image
  ! grep -q 'amd-ucode' "$ROOT/boot/efi/loader/entries/arch.conf"
}
