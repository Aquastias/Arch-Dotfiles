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
  local entry_file="$ESP/loader/entries/$1.conf" kernel="$2"
  shift 2
  {
    echo "title   test"
    echo "linux   /$kernel"
    local i
    for i in "$@"; do echo "initrd  /$i"; done
    echo "options root=ZFS=rpool/ROOT/arch rw"
  } >"$entry_file"
}

in_output() { printf '%s\n' "$output" | grep -qxF "$1"; }

# zero_file <bytes> <path> — a <bytes>-long file of zeros.
zero_file() { : >"$2"; truncate -s "$1" "$2"; }

@test "planner emits entry-referenced files and excludes a stray kernel" {
  _entry arch-zfs vmlinuz-linux-lts intel-ucode.img initramfs-linux-lts.img
  : >"$BOOT/vmlinuz-linux-lts"
  : >"$BOOT/intel-ucode.img"
  : >"$BOOT/initramfs-linux-lts.img"
  # a stray rolling kernel present in /boot but named by NO entry
  : >"$BOOT/vmlinuz-linux"
  : >"$BOOT/initramfs-linux.img"

  run esp_kernel_sync_planned_files "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  in_output vmlinuz-linux-lts
  in_output intel-ucode.img
  in_output initramfs-linux-lts.img
  ! in_output vmlinuz-linux || return 1
  ! in_output initramfs-linux.img
}

@test "planner mirrors every kernel across multiple entries (ADR 0078)" {
  # Two selected kernels → two entry files, each naming its own images; the
  # planner must mirror all of them, while a stray rolling kernel stays out.
  _entry arch-linux-lts vmlinuz-linux-lts amd-ucode.img initramfs-linux-lts.img
  _entry arch-linux-zen vmlinuz-linux-zen amd-ucode.img initramfs-linux-zen.img
  : >"$BOOT/vmlinuz-linux-lts"; : >"$BOOT/initramfs-linux-lts.img"
  : >"$BOOT/vmlinuz-linux-zen"; : >"$BOOT/initramfs-linux-zen.img"
  : >"$BOOT/amd-ucode.img"
  : >"$BOOT/vmlinuz-linux"; : >"$BOOT/initramfs-linux.img"  # stray

  run esp_kernel_sync_planned_files "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  in_output vmlinuz-linux-lts
  in_output initramfs-linux-lts.img
  in_output vmlinuz-linux-zen
  in_output initramfs-linux-zen.img
  in_output amd-ucode.img
  ! in_output vmlinuz-linux || return 1
  ! in_output initramfs-linux.img
}

@test "planner omits an entry-referenced file missing from /boot" {
  _entry arch-zfs vmlinuz-linux-lts intel-ucode.img initramfs-linux-lts.img
  : >"$BOOT/vmlinuz-linux-lts" # only this one exists in /boot
  run esp_kernel_sync_planned_files "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  in_output vmlinuz-linux-lts
  ! in_output intel-ucode.img || return 1
  ! in_output initramfs-linux-lts.img
}

@test "planner mirrors ESP-root boot images with no loader entries (grub etc.)" {
  # GRUB/Limine/rEFInd/EFISTUB stage kernels at the ESP root and keep no
  # loader/entries; their kernel upgrades must still reach the ESP.
  rmdir "$ESP/loader/entries" "$ESP/loader"
  local image
  for image in vmlinuz-linux-lts initramfs-linux-lts.img \
           initramfs-linux-lts-fallback.img intel-ucode.img; do
    echo new >"$BOOT/$image"; echo old >"$ESP/$image"
  done
  run esp_kernel_sync_planned_files "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  in_output vmlinuz-linux-lts
  in_output initramfs-linux-lts.img
  in_output initramfs-linux-lts-fallback.img
  in_output intel-ucode.img
}

@test "planner never mirrors a kernel that was not staged on the ESP" {
  rmdir "$ESP/loader/entries" "$ESP/loader"
  echo new >"$BOOT/vmlinuz-linux-lts"; echo old >"$ESP/vmlinuz-linux-lts"
  echo stray >"$BOOT/vmlinuz-linux-zen"   # Stray Kernel: /boot only
  run esp_kernel_sync_planned_files "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  in_output vmlinuz-linux-lts
  ! in_output vmlinuz-linux-zen
}

@test "planner de-duplicates a file referenced by multiple entries" {
  _entry arch-zfs vmlinuz-linux-lts intel-ucode.img initramfs-linux-lts.img
  _entry arch-zfs-fallback vmlinuz-linux-lts intel-ucode.img \
    initramfs-linux-lts-fallback.img
  : >"$BOOT/vmlinuz-linux-lts"
  : >"$BOOT/intel-ucode.img"
  : >"$BOOT/initramfs-linux-lts.img"
  : >"$BOOT/initramfs-linux-lts-fallback.img"

  run esp_kernel_sync_planned_files "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  # vmlinuz-linux-lts is referenced by both entries — appears exactly once
  [ "$(printf '%s\n' "$output" | grep -cxF vmlinuz-linux-lts)" -eq 1 ]
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

  run esp_kernel_sync_critical_files "$ESP" "$BOOT"
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

  run esp_kernel_sync_optional_files "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  in_output initramfs-linux-lts-fallback.img
  ! in_output vmlinuz-linux-lts || return 1
  ! in_output initramfs-linux-lts.img
}

# ── install_critical: temp+rename + cmp; preserve old image on failure ────

@test "install_critical success: dst byte-equals src, returns 0, no .new" {
  printf 'NEWIMG' >"$BOOT/src.img"
  printf 'OLDIMG' >"$ESP/dst.img"
  run esp_kernel_sync_install_critical "$BOOT/src.img" "$ESP/dst.img"
  [ "$status" -eq 0 ]
  [ "$(cat "$ESP/dst.img")" = "NEWIMG" ]
  cmp -s "$BOOT/src.img" "$ESP/dst.img"
  [ ! -e "$ESP/dst.img.new" ]
}

@test "install_critical failure preserves old dst, non-zero, no .new" {
  printf 'OLDIMG' >"$ESP/dst.img"
  run esp_kernel_sync_install_critical "$BOOT/missing.img" "$ESP/dst.img"
  [ "$status" -ne 0 ]
  [ "$(cat "$ESP/dst.img")" = "OLDIMG" ] # prior good image intact
  [ ! -e "$ESP/dst.img.new" ]
}

# ── orphan_temps: list .new temps for the sweep ───────────────────────────

@test "orphan_temps lists .new temp files, not real files" {
  : >"$ESP/.vmlinuz-linux-lts.new"
  : >"$ESP/.initramfs-linux-lts.img.new"
  : >"$ESP/vmlinuz-linux-lts"
  run esp_kernel_sync_orphan_temporaries "$ESP"
  [ "$status" -eq 0 ]
  in_output "$ESP/.vmlinuz-linux-lts.new"
  in_output "$ESP/.initramfs-linux-lts.img.new"
  ! in_output "$ESP/vmlinuz-linux-lts"
}

# ── space proxy (needed_bytes / space_ok) ─────────────────────────────────

@test "needed_bytes = sum of planned file sizes plus the largest (headroom)" {
  _entry arch-zfs vmlinuz-linux-lts intel-ucode.img initramfs-linux-lts.img
  zero_file 100 "$BOOT/vmlinuz-linux-lts"
  zero_file 50 "$BOOT/intel-ucode.img"
  zero_file 200 "$BOOT/initramfs-linux-lts.img"
  run esp_kernel_sync_needed_bytes "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  [ "$output" -eq 550 ] # 100 + 50 + 200, plus 200 (largest) for temp+rename
}

@test "space_ok: ample free passes, tight free fails" {
  _entry arch-zfs vmlinuz-linux-lts initramfs-linux-lts.img
  zero_file 100 "$BOOT/vmlinuz-linux-lts"
  zero_file 200 "$BOOT/initramfs-linux-lts.img"
  # needed = 100 + 200 + 200 (largest) = 500; ESP empty -> present = 0
  run esp_kernel_sync_space_ok "$ESP" "$BOOT" 1000
  [ "$status" -eq 0 ]
  run esp_kernel_sync_space_ok "$ESP" "$BOOT" 400
  [ "$status" -ne 0 ]
}

@test "present_bytes = sizes of planned files already on the ESP" {
  _entry arch-zfs vmlinuz-linux-lts initramfs-linux-lts.img
  zero_file 100 "$BOOT/vmlinuz-linux-lts"
  zero_file 200 "$BOOT/initramfs-linux-lts.img"
  # only the initramfs already exists on the ESP (the vmlinuz is new)
  zero_file 200 "$ESP/initramfs-linux-lts.img"
  run esp_kernel_sync_present_bytes "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  [ "$output" -eq 200 ]
}

@test "space_ok: a populated ESP does not false-abort a re-sync" {
  _entry arch-zfs vmlinuz-linux-lts initramfs-linux-lts.img
  zero_file 100 "$BOOT/vmlinuz-linux-lts"
  zero_file 200 "$BOOT/initramfs-linux-lts.img"
  # steady state: the same images are already on the ESP (present = 300)
  zero_file 100 "$ESP/vmlinuz-linux-lts"
  zero_file 200 "$ESP/initramfs-linux-lts.img"
  # needed = 500; free + present >= needed  =>  free >= 200.
  # 250 used to fail the old free-only check (250 < 500); now it passes.
  run esp_kernel_sync_space_ok "$ESP" "$BOOT" 250
  [ "$status" -eq 0 ]
  # a genuinely-too-small ESP still fails: 150 + 300 = 450 < 500.
  run esp_kernel_sync_space_ok "$ESP" "$BOOT" 150
  [ "$status" -ne 0 ]
}

# ── preflight guards: mountpoint + script exec-ability ────────────────────

@test "is_mountpoint: true only when the dir is a mount target" {
  printf '%s\n' \
    "rpool/ROOT/arch / zfs rw 0 0" \
    "/dev/sda1 /boot/efi vfat rw 0 0" >"$BOOT/mounts"
  run esp_kernel_sync_is_mountpoint /boot/efi "$BOOT/mounts"
  [ "$status" -eq 0 ]
  # the runtime passes the glob form with a trailing slash — still matches
  run esp_kernel_sync_is_mountpoint /boot/efi/ "$BOOT/mounts"
  [ "$status" -eq 0 ]
  # a directory that is NOT mounted (ESP absent) fails
  run esp_kernel_sync_is_mountpoint /boot/efi1 "$BOOT/mounts"
  [ "$status" -ne 0 ]
}

@test "script_ok: requires a #! shebang and the executable bit" {
  local script_file="$BOOT/sync.sh"
  printf '#!/usr/bin/env bash\necho hi\n' >"$script_file"
  chmod +x "$script_file"
  run esp_kernel_sync_script_ok "$script_file"
  [ "$status" -eq 0 ]

  # no shebang -> would ENOEXEC under execv -> rejected
  printf '# not a shebang\necho hi\n' >"$script_file"
  chmod +x "$script_file"
  run esp_kernel_sync_script_ok "$script_file"
  [ "$status" -ne 0 ]

  # shebang present but not executable -> rejected
  printf '#!/usr/bin/env bash\n' >"$script_file"
  chmod -x "$script_file"
  run esp_kernel_sync_script_ok "$script_file"
  [ "$status" -ne 0 ]
}

# ── prune_dead_fallback_entries: dead entry removed; status never leaks ────

@test "prune drops a fallback entry whose image is absent, keeps the default" {
  _entry arch-zfs vmlinuz-linux-lts initramfs-linux-lts.img
  _entry arch-zfs-fallback vmlinuz-linux-lts initramfs-linux-lts-fallback.img
  # the fallback IMAGE is NOT on the ESP -> its entry must be pruned
  run esp_kernel_sync_prune_dead_fallback_entries "$ESP"
  [ "$status" -eq 0 ]
  [ -f "$ESP/loader/entries/arch-zfs.conf" ]
  [ ! -f "$ESP/loader/entries/arch-zfs-fallback.conf" ]
}

@test "prune keeps a fallback entry whose image is present, returns 0" {
  _entry arch-zfs-fallback vmlinuz-linux-lts initramfs-linux-lts-fallback.img
  : >"$ESP/initramfs-linux-lts-fallback.img" # present -> keep the entry
  run esp_kernel_sync_prune_dead_fallback_entries "$ESP"
  [ "$status" -eq 0 ]
  [ -f "$ESP/loader/entries/arch-zfs-fallback.conf" ]
}

@test "prune returns 0 on a normal run with no fallback entry to drop" {
  # the regression: the trailing *fallback* test used to leak status 1 here,
  # which became the sync hook's exit code ("command failed to execute").
  _entry arch-zfs vmlinuz-linux-lts intel-ucode.img initramfs-linux-lts.img
  run esp_kernel_sync_prune_dead_fallback_entries "$ESP"
  [ "$status" -eq 0 ]
  [ -f "$ESP/loader/entries/arch-zfs.conf" ]
}

# ── previous kernel pairs (ADR 0166) ──────────────────────────────────────────

@test "stale_previous lists kernels whose -prev pair is missing or old" {
  echo new >"$ESP/vmlinuz-linux-lts"; echo old >"$ESP/vmlinuz-linux-lts-prev"
  echo same >"$ESP/vmlinuz-linux"; echo same >"$ESP/vmlinuz-linux-prev"
  echo i >"$ESP/initramfs-linux.img"; echo i >"$ESP/initramfs-linux-prev.img"
  echo k >"$ESP/vmlinuz-linux-zen"
  run esp_kernel_sync_stale_previous "$ESP"
  [ "$status" -eq 0 ]
  [ "$output" = $'linux-lts\nlinux-zen' ]
}

@test "keep_previous copies the current pair to -prev names" {
  echo k-old >"$ESP/vmlinuz-linux-lts"
  echo i-old >"$ESP/initramfs-linux-lts.img"
  run esp_kernel_sync_keep_previous "$ESP" linux-lts
  [ "$status" -eq 0 ]
  [ "$(cat "$ESP/vmlinuz-linux-lts-prev")" = k-old ]
  [ "$(cat "$ESP/initramfs-linux-lts-prev.img")" = i-old ]
  [ "$(cat "$ESP/vmlinuz-linux-lts")" = k-old ]
  [ -z "$(esp_kernel_sync_orphan_temporaries "$ESP")" ]
}

@test "drop_previous removes a kernel's -prev pair only" {
  : >"$ESP/vmlinuz-linux-lts-prev"; : >"$ESP/initramfs-linux-lts-prev.img"
  : >"$ESP/vmlinuz-linux-prev"
  esp_kernel_sync_drop_previous "$ESP" linux-lts
  [ ! -e "$ESP/vmlinuz-linux-lts-prev" ]
  [ ! -e "$ESP/initramfs-linux-lts-prev.img" ]
  [ -e "$ESP/vmlinuz-linux-prev" ]
}

@test "pair_bytes = current kernel + default initramfs on the ESP" {
  zero_file 100 "$ESP/vmlinuz-linux-lts"
  zero_file 50 "$ESP/initramfs-linux-lts.img"
  zero_file 999 "$ESP/initramfs-linux-lts-fallback.img"
  [ "$(esp_kernel_sync_pair_bytes "$ESP" linux-lts)" -eq 150 ]
}

@test "planner never mirrors a -prev image" {
  echo new >"$BOOT/vmlinuz-linux-lts"; echo old >"$ESP/vmlinuz-linux-lts"
  echo old >"$ESP/vmlinuz-linux-lts-prev"
  echo old >"$ESP/initramfs-linux-lts-prev.img"
  run esp_kernel_sync_planned_files "$ESP" "$BOOT"
  [ "$output" = vmlinuz-linux-lts ]
}

@test "previous_fits: keeps the pair only when room remains after the sync" {
  zero_file 100 "$ESP/vmlinuz-linux-lts"
  zero_file 100 "$ESP/initramfs-linux-lts.img"
  zero_file 100 "$BOOT/vmlinuz-linux-lts"
  zero_file 100 "$BOOT/initramfs-linux-lts.img"
  # needed 300 (200 + largest 100), present 200 → slack = free - 100
  run esp_kernel_sync_previous_fits "$ESP" "$BOOT" 300 linux-lts
  [ "$status" -eq 0 ]
  run esp_kernel_sync_previous_fits "$ESP" "$BOOT" 299 linux-lts
  [ "$status" -ne 0 ]
}

@test "previous hook: every transaction, PreTransaction, never aborts" {
  run esp_kernel_sync_previous_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"Type = Package"* ]]
  [[ "$output" == *"Target = *"* ]]
  [[ "$output" == *"When = PreTransaction"* ]]
  [[ "$output" == *"esp-kernel-sync.sh previous"* ]]
  [[ "$output" != *AbortOnFail* ]]
}

# ── install (ADR 0038 / 0166) ────────────────────────────────────────────────

@test "install: script + hooks; guards sort before 60-mkinitcpio-remove" {
  local root="$ESP/root" hooks="$ESP/root/etc/pacman.d/hooks"
  mkdir -p "$hooks"
  : >"$hooks/93-esp-kernel-sync-preflight.hook"
  : >"$hooks/91-esp-previous-pair.hook"
  esp_kernel_sync_install "$root" \
    "$BATS_TEST_DIRNAME/../../lib/boot/esp-kernel-sync.sh"
  [ -x "$root/usr/local/lib/archzfs/esp-kernel-sync.sh" ]
  grep -q "AbortOnFail" "$hooks/01-esp-kernel-sync-preflight.hook"
  grep -q "esp-kernel-sync.sh previous" "$hooks/03-esp-previous-pair.hook"
  grep -q "When = PostTransaction" "$hooks/94-esp-kernel-sync.hook"
  # pacman runs hooks by filename; 60-mkinitcpio-remove deletes /boot images
  [[ "01-esp-kernel-sync-preflight.hook" < "60-mkinitcpio-remove.hook" ]]
  [[ "03-esp-previous-pair.hook" < "60-mkinitcpio-remove.hook" ]]
  # the old, too-late names are gone
  [ ! -e "$hooks/93-esp-kernel-sync-preflight.hook" ]
  [ ! -e "$hooks/91-esp-previous-pair.hook" ]
}

@test "stale_previous: an initramfs-only rebuild makes the pair stale" {
  echo k >"$ESP/vmlinuz-linux-lts"; echo k >"$ESP/vmlinuz-linux-lts-prev"
  echo new >"$ESP/initramfs-linux-lts.img"
  echo old >"$ESP/initramfs-linux-lts-prev.img"
  run esp_kernel_sync_stale_previous "$ESP"
  [ "$output" = linux-lts ]
}

# ── every-transaction sync (initramfs-only rebuilds) ─────────────────────────

@test "sync hook: runs after every transaction, after mkinitcpio's 90-" {
  run esp_kernel_sync_sync_hook
  [[ "$output" == *"Type = Package"* && "$output" == *"Target = *"* ]]
  [[ "$output" == *"When = PostTransaction"* ]]
  [[ "90-mkinitcpio-install.hook" < "94-esp-kernel-sync.hook" ]]
}

@test "install_critical: an identical file is left untouched (no FAT write)" {
  echo same >"$BOOT/initramfs-linux-lts.img"
  echo same >"$ESP/initramfs-linux-lts.img"
  local before
  before="$(stat -c %i "$ESP/initramfs-linux-lts.img")"
  esp_kernel_sync_install_critical "$BOOT/initramfs-linux-lts.img" \
    "$ESP/initramfs-linux-lts.img"
  [ "$(stat -c %i "$ESP/initramfs-linux-lts.img")" = "$before" ]
}

@test "kernels_current: every staged kernel present in /boot and equal" {
  echo k >"$BOOT/vmlinuz-linux-lts"; echo k >"$ESP/vmlinuz-linux-lts"
  echo p >"$ESP/vmlinuz-linux-lts-prev"
  run esp_kernel_sync_kernels_current "$ESP" "$BOOT"
  [ "$status" -eq 0 ]
  # an interrupted update: /boot lost its kernel, the ESP kept the old one
  rm "$BOOT/vmlinuz-linux-lts"
  run esp_kernel_sync_kernels_current "$ESP" "$BOOT"
  [ "$status" -ne 0 ]
}
