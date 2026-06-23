#!/usr/bin/env bats
# Tests for lib/boot/esp-kernel-sync.sh — the ESP Kernel Sync planner.
#
# Sourced lib-only (ESP_KERNEL_SYNC_LIB_ONLY=1) so the runtime cp loop is
# skipped and only the pure planner is exercised (mirrors initcpio.sh's
# INITCPIO_LIB_ONLY guard). The planner drives the sync from the loader
# entries, so a Stray Kernel — which has no entry — is never mirrored.

setup() {
  ESP_KERNEL_SYNC_LIB_ONLY=1
  # shellcheck source=../../lib/boot/esp-kernel-sync.sh
  source "$BATS_TEST_DIRNAME/../../lib/boot/esp-kernel-sync.sh"

  ESP="$(mktemp -d)"
  BOOT="$(mktemp -d)"
  mkdir -p "$ESP/loader/entries"
}

teardown() { rm -rf "$ESP" "$BOOT"; }

# Write a loader entry: _entry <name> <vmlinuz> <initrd>...
_entry() {
  local f="$ESP/loader/entries/$1.conf" kernel="$2"
  shift 2
  {
    echo "title   test"
    echo "linux   /$kernel"
    local i
    for i in "$@"; do echo "initrd  /$i"; done
    echo "options root=ZFS=rpool/ROOT/arch rw"
  } >"$f"
}

in_output() { grep -qxF "$1" <<<"$output"; }

@test "planner emits entry-referenced files and excludes a stray kernel" {
  _entry arch-zfs vmlinuz-linux-lts intel-ucode.img initramfs-linux-lts.img
  : >"$BOOT/vmlinuz-linux-lts"
  : >"$BOOT/intel-ucode.img"
  : >"$BOOT/initramfs-linux-lts.img"
  # a stray rolling kernel present in /boot but named by NO entry
  : >"$BOOT/vmlinuz-linux"
  : >"$BOOT/initramfs-linux.img"

  run esp_sync_planned_files "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  in_output vmlinuz-linux-lts
  in_output intel-ucode.img
  in_output initramfs-linux-lts.img
  ! in_output vmlinuz-linux
  ! in_output initramfs-linux.img
}

@test "planner omits an entry-referenced file missing from /boot" {
  _entry arch-zfs vmlinuz-linux-lts intel-ucode.img initramfs-linux-lts.img
  : >"$BOOT/vmlinuz-linux-lts" # only this one exists in /boot
  run esp_sync_planned_files "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  in_output vmlinuz-linux-lts
  ! in_output intel-ucode.img
  ! in_output initramfs-linux-lts.img
}

@test "planner de-duplicates a file referenced by multiple entries" {
  _entry arch-zfs vmlinuz-linux-lts intel-ucode.img initramfs-linux-lts.img
  _entry arch-zfs-fallback vmlinuz-linux-lts intel-ucode.img \
    initramfs-linux-lts-fallback.img
  : >"$BOOT/vmlinuz-linux-lts"
  : >"$BOOT/intel-ucode.img"
  : >"$BOOT/initramfs-linux-lts.img"
  : >"$BOOT/initramfs-linux-lts-fallback.img"

  run esp_sync_planned_files "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  # vmlinuz-linux-lts is referenced by both entries — appears exactly once
  [ "$(grep -cxF vmlinuz-linux-lts <<<"$output")" -eq 1 ]
  in_output initramfs-linux-lts-fallback.img
}

# ── critical vs optional classification (by *fallback* filename) ──────────

@test "critical files = entry-referenced non-fallback files" {
  _entry arch-zfs vmlinuz-linux-lts intel-ucode.img initramfs-linux-lts.img
  _entry arch-zfs-fallback vmlinuz-linux-lts intel-ucode.img \
    initramfs-linux-lts-fallback.img
  : >"$BOOT/vmlinuz-linux-lts"
  : >"$BOOT/intel-ucode.img"
  : >"$BOOT/initramfs-linux-lts.img"
  : >"$BOOT/initramfs-linux-lts-fallback.img"

  run esp_sync_critical_files "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  in_output vmlinuz-linux-lts
  in_output intel-ucode.img
  in_output initramfs-linux-lts.img
  ! in_output initramfs-linux-lts-fallback.img
}

@test "optional files = entry-referenced fallback files only" {
  _entry arch-zfs vmlinuz-linux-lts intel-ucode.img initramfs-linux-lts.img
  _entry arch-zfs-fallback vmlinuz-linux-lts intel-ucode.img \
    initramfs-linux-lts-fallback.img
  : >"$BOOT/vmlinuz-linux-lts"
  : >"$BOOT/intel-ucode.img"
  : >"$BOOT/initramfs-linux-lts.img"
  : >"$BOOT/initramfs-linux-lts-fallback.img"

  run esp_sync_optional_files "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  in_output initramfs-linux-lts-fallback.img
  ! in_output vmlinuz-linux-lts
  ! in_output initramfs-linux-lts.img
}

# ── install_critical: temp+rename + cmp; preserve old image on failure ────

@test "install_critical success: dst byte-equals src, returns 0, no .new" {
  printf 'NEWIMG' >"$BOOT/src.img"
  printf 'OLDIMG' >"$ESP/dst.img"
  run esp_sync_install_critical "$BOOT/src.img" "$ESP/dst.img"
  [ "$status" -eq 0 ]
  [ "$(cat "$ESP/dst.img")" = "NEWIMG" ]
  cmp -s "$BOOT/src.img" "$ESP/dst.img"
  [ ! -e "$ESP/dst.img.new" ]
}

@test "install_critical failure preserves old dst, non-zero, no .new" {
  printf 'OLDIMG' >"$ESP/dst.img"
  run esp_sync_install_critical "$BOOT/missing.img" "$ESP/dst.img"
  [ "$status" -ne 0 ]
  [ "$(cat "$ESP/dst.img")" = "OLDIMG" ] # prior good image intact
  [ ! -e "$ESP/dst.img.new" ]
}

# ── orphan_temps: list .new temps for the sweep ───────────────────────────

@test "orphan_temps lists .new temp files, not real files" {
  : >"$ESP/.vmlinuz-linux-lts.new"
  : >"$ESP/.initramfs-linux-lts.img.new"
  : >"$ESP/vmlinuz-linux-lts"
  run esp_sync_orphan_temps "$ESP"
  [ "$status" -eq 0 ]
  in_output "$ESP/.vmlinuz-linux-lts.new"
  in_output "$ESP/.initramfs-linux-lts.img.new"
  ! in_output "$ESP/vmlinuz-linux-lts"
}

# ── space proxy (needed_bytes / space_ok) ─────────────────────────────────

@test "needed_bytes = sum of planned file sizes plus the largest (headroom)" {
  _entry arch-zfs vmlinuz-linux-lts intel-ucode.img initramfs-linux-lts.img
  head -c 100 /dev/zero >"$BOOT/vmlinuz-linux-lts"
  head -c 50 /dev/zero >"$BOOT/intel-ucode.img"
  head -c 200 /dev/zero >"$BOOT/initramfs-linux-lts.img"
  run esp_sync_needed_bytes "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  [ "$output" -eq 550 ] # 100 + 50 + 200, plus 200 (largest) for temp+rename
}

@test "space_ok: ample free passes, tight free fails" {
  _entry arch-zfs vmlinuz-linux-lts initramfs-linux-lts.img
  head -c 100 /dev/zero >"$BOOT/vmlinuz-linux-lts"
  head -c 200 /dev/zero >"$BOOT/initramfs-linux-lts.img"
  # needed = 100 + 200 + 200 (largest) = 500; ESP empty -> present = 0
  run esp_sync_space_ok "$ESP" "$BOOT" 1000
  [ "$status" -eq 0 ]
  run esp_sync_space_ok "$ESP" "$BOOT" 400
  [ "$status" -ne 0 ]
}

@test "present_bytes = sizes of planned files already on the ESP" {
  _entry arch-zfs vmlinuz-linux-lts initramfs-linux-lts.img
  head -c 100 /dev/zero >"$BOOT/vmlinuz-linux-lts"
  head -c 200 /dev/zero >"$BOOT/initramfs-linux-lts.img"
  # only the initramfs already exists on the ESP (the vmlinuz is new)
  head -c 200 /dev/zero >"$ESP/initramfs-linux-lts.img"
  run esp_sync_present_bytes "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  [ "$output" -eq 200 ]
}

@test "space_ok: a populated ESP does not false-abort a re-sync" {
  _entry arch-zfs vmlinuz-linux-lts initramfs-linux-lts.img
  head -c 100 /dev/zero >"$BOOT/vmlinuz-linux-lts"
  head -c 200 /dev/zero >"$BOOT/initramfs-linux-lts.img"
  # steady state: the same images are already on the ESP (present = 300)
  head -c 100 /dev/zero >"$ESP/vmlinuz-linux-lts"
  head -c 200 /dev/zero >"$ESP/initramfs-linux-lts.img"
  # needed = 500; free + present >= needed  =>  free >= 200.
  # 250 used to fail the old free-only check (250 < 500); now it passes.
  run esp_sync_space_ok "$ESP" "$BOOT" 250
  [ "$status" -eq 0 ]
  # a genuinely-too-small ESP still fails: 150 + 300 = 450 < 500.
  run esp_sync_space_ok "$ESP" "$BOOT" 150
  [ "$status" -ne 0 ]
}

# ── preflight guards: mountpoint + script exec-ability ────────────────────

@test "is_mountpoint: true only when the dir is a mount target" {
  printf '%s\n' \
    "rpool/ROOT/arch / zfs rw 0 0" \
    "/dev/sda1 /boot/efi vfat rw 0 0" >"$BOOT/mounts"
  run esp_sync_is_mountpoint /boot/efi "$BOOT/mounts"
  [ "$status" -eq 0 ]
  # the runtime passes the glob form with a trailing slash — still matches
  run esp_sync_is_mountpoint /boot/efi/ "$BOOT/mounts"
  [ "$status" -eq 0 ]
  # a directory that is NOT mounted (ESP absent) fails
  run esp_sync_is_mountpoint /boot/efi1 "$BOOT/mounts"
  [ "$status" -ne 0 ]
}

@test "script_ok: requires a #! shebang and the executable bit" {
  local s="$BOOT/sync.sh"
  printf '#!/usr/bin/env bash\necho hi\n' >"$s"
  chmod +x "$s"
  run esp_sync_script_ok "$s"
  [ "$status" -eq 0 ]

  # no shebang -> would ENOEXEC under execv -> rejected
  printf '# not a shebang\necho hi\n' >"$s"
  chmod +x "$s"
  run esp_sync_script_ok "$s"
  [ "$status" -ne 0 ]

  # shebang present but not executable -> rejected
  printf '#!/usr/bin/env bash\n' >"$s"
  chmod -x "$s"
  run esp_sync_script_ok "$s"
  [ "$status" -ne 0 ]
}

# ── prune_dead_fallback_entries: dead entry removed; status never leaks ────

@test "prune drops a fallback entry whose image is absent, keeps the default" {
  _entry arch-zfs vmlinuz-linux-lts initramfs-linux-lts.img
  _entry arch-zfs-fallback vmlinuz-linux-lts initramfs-linux-lts-fallback.img
  # the fallback IMAGE is NOT on the ESP -> its entry must be pruned
  run esp_sync_prune_dead_fallback_entries "$ESP"
  [ "$status" -eq 0 ]
  [ -f "$ESP/loader/entries/arch-zfs.conf" ]
  [ ! -f "$ESP/loader/entries/arch-zfs-fallback.conf" ]
}

@test "prune keeps a fallback entry whose image is present, returns 0" {
  _entry arch-zfs-fallback vmlinuz-linux-lts initramfs-linux-lts-fallback.img
  : >"$ESP/initramfs-linux-lts-fallback.img" # present -> keep the entry
  run esp_sync_prune_dead_fallback_entries "$ESP"
  [ "$status" -eq 0 ]
  [ -f "$ESP/loader/entries/arch-zfs-fallback.conf" ]
}

@test "prune returns 0 on a normal run with no fallback entry to drop" {
  # the regression: the trailing *fallback* test used to leak status 1 here,
  # which became the sync hook's exit code ("command failed to execute").
  _entry arch-zfs vmlinuz-linux-lts intel-ucode.img initramfs-linux-lts.img
  run esp_sync_prune_dead_fallback_entries "$ESP"
  [ "$status" -eq 0 ]
  [ -f "$ESP/loader/entries/arch-zfs.conf" ]
}
