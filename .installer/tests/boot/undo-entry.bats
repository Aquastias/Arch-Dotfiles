#!/usr/bin/env bats
# Tests for lib/boot/undo-entry.sh — the Undo Last Update boot entry
# (ADR 0166). Sourced lib-only (UNDO_ENTRY_LIB_ONLY=1): renderers are pure and
# the reconcile step works on a temp ESP.

setup() {
  UNDO_ENTRY_LIB_ONLY=1
  # shellcheck source=../../lib/boot/undo-entry.sh
  source "$BATS_TEST_DIRNAME/../../lib/boot/undo-entry.sh"
  ESP="$(mktemp -d)"
  CMDLINE="root=ZFS=rpool/ROOT/arch rw"
}

teardown() { rm -rf "$ESP"; }

@test "render systemd-boot: previous pair, microcode first, undo parameter" {
  run undo_entry_render systemd-boot linux-lts amd-ucode.img "$CMDLINE"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' 'title   Undo Last Update' \
    'linux   /vmlinuz-linux-lts-prev' 'initrd  /amd-ucode.img' \
    'initrd  /initramfs-linux-lts-prev.img' \
    'options root=ZFS=rpool/ROOT/arch rw undo_last_update')" ]
}

@test "render limine and grub: the previous pair with the undo parameter" {
  run undo_entry_render limine linux-lts "" "$CMDLINE"
  [[ "$output" == *"kernel_path: boot():/vmlinuz-linux-lts-prev"* ]]
  [[ "$output" == *"module_path: boot():/initramfs-linux-lts-prev.img"* ]]
  [[ "$output" == *"cmdline: $CMDLINE undo_last_update"* ]]
  run undo_entry_render grub linux-lts intel-ucode.img "$CMDLINE"
  [[ "$output" == *"menuentry 'Undo Last Update'"* ]]
  [[ "$output" == *"linux /vmlinuz-linux-lts-prev $CMDLINE undo_last_update"* ]]
  [[ "$output" == *"initrd /intel-ucode.img /initramfs-linux-lts-prev.img"* ]]
}

@test "render refind: manual stanza, microcode as initrd= in options" {
  run undo_entry_render refind linux-lts amd-ucode.img "$CMDLINE"
  [[ "$output" == *'menuentry "Undo Last Update" {'* ]]
  [[ "$output" == *"loader  /vmlinuz-linux-lts-prev"* ]]
  [[ "$output" == *"initrd  /initramfs-linux-lts-prev.img"* ]]
  local options='options "initrd=\amd-ucode.img '"$CMDLINE"' undo_last_update"'
  [[ "$output" == *"$options"* ]]
}

@test "render efistub: load options for the previous pair" {
  run undo_entry_render efistub linux-lts amd-ucode.img "$CMDLINE"
  [ "$output" = \
    "initrd=\\amd-ucode.img initrd=\\initramfs-linux-lts-prev.img $CMDLINE"\
" undo_last_update" ]
}

@test "refind_hide: keeps previous kernels out of rEFInd's autodetection" {
  run undo_entry_refind_hide linux-lts linux
  [ "$output" = "dont_scan_files + vmlinuz-linux-lts-prev,vmlinuz-linux-prev" ]
}

# _previous_pair — fake the Primary Kernel's previous pair on the ESP.
_previous_pair() {
  : >"$ESP/vmlinuz-linux-lts-prev"
  : >"$ESP/initramfs-linux-lts-prev.img"
}

@test "reconcile systemd-boot: entry present only with a previous pair" {
  mkdir -p "$ESP/loader/entries"
  echo template >"$ESP/template"
  undo_entry_reconcile "$ESP" systemd-boot linux-lts "$ESP/template"
  [ ! -e "$ESP/loader/entries/arch-undo.conf" ]
  _previous_pair
  undo_entry_reconcile "$ESP" systemd-boot linux-lts "$ESP/template"
  [ "$(cat "$ESP/loader/entries/arch-undo.conf")" = template ]
  rm "$ESP/initramfs-linux-lts-prev.img"
  undo_entry_reconcile "$ESP" systemd-boot linux-lts "$ESP/template"
  [ ! -e "$ESP/loader/entries/arch-undo.conf" ]
}

@test "reconcile limine: one marked block appended, removed when absent" {
  printf 'timeout: 4\n\n/Arch Linux\n' >"$ESP/limine.conf"
  echo "/Undo Last Update" >"$ESP/template"
  _previous_pair
  undo_entry_reconcile "$ESP" limine linux-lts "$ESP/template"
  undo_entry_reconcile "$ESP" limine linux-lts "$ESP/template"
  [ "$(grep -c 'Undo Last Update' "$ESP/limine.conf")" -eq 1 ]
  rm "$ESP/vmlinuz-linux-lts-prev"
  undo_entry_reconcile "$ESP" limine linux-lts "$ESP/template"
  ! grep -q 'undo' "$ESP/limine.conf"
  [ "$(cat "$ESP/limine.conf")" = "$(printf 'timeout: 4\n\n/Arch Linux')" ]
}

@test "reconcile grub and refind edit their own config files" {
  mkdir -p "$ESP/grub" "$ESP/EFI/refind"
  echo "set default=0" >"$ESP/grub/grub.cfg"
  echo "timeout 5" >"$ESP/EFI/refind/refind.conf"
  echo "UNDO" >"$ESP/template"
  _previous_pair
  undo_entry_reconcile "$ESP" grub linux-lts "$ESP/template"
  undo_entry_reconcile "$ESP" refind linux-lts "$ESP/template"
  grep -qx UNDO "$ESP/grub/grub.cfg"
  grep -qx UNDO "$ESP/EFI/refind/refind.conf"
}

@test "reconcile efistub: firmware entry is fixed, nothing to edit" {
  _previous_pair
  run undo_entry_reconcile "$ESP" efistub linux-lts "$ESP/template"
  [ "$status" -eq 0 ]
}

# ── initramfs undo-update hook ───────────────────────────────────────────────

# _run_hook <cmdline> — run the rendered hook's latehook against a stub zfs
# whose datasets/snapshots come from $ZFS_LIST; every rollback/rename is logged.
_run_hook() {
  local hook="$ESP/undo-update"
  undo_entry_initcpio_hook >"$hook"
  echo "$1" >"$ESP/cmdline"
  # Only the tools verified present in the initramfs busybox (it has no tr).
  local bin="$ESP/initramfs-bin" tool
  mkdir -p "$bin"
  for tool in cat sed awk sort grep; do ln -sf "$(command -v "$tool")" "$bin/"; done
  PATH="$bin" run /usr/bin/bash -c '
    zfs() {
      case "$1 $2" in
      "list -H") case "$*" in
        *"-t snapshot"*) printf "%s\n" $SNAPSHOTS ;;
        *"@"*) printf "%s\n" $SNAPSHOTS | grep -qx "${@: -1}" ;;
        *) printf "%s\n" $DATASETS ;;
        esac ;;
      *) echo "zfs $*" >>"$LOG" ;;
      esac
    }
    msg() { :; }; err() { echo "ERR $*"; }
    . "$1"; run_latehook; cat "$LOG" 2>/dev/null' _ "$hook"
}

@test "hook: does nothing without the undo parameter" {
  export UNDO_CMDLINE="$ESP/cmdline" LOG="$ESP/log"
  export DATASETS="rpool/ROOT/arch" SNAPSHOTS="rpool/ROOT/arch@update-1"
  _run_hook "root=ZFS=rpool/ROOT/arch rw"
  [ -z "$output" ]
}

@test "hook: rolls every dataset back to the newest Update Snapshot" {
  export UNDO_CMDLINE="$ESP/cmdline" LOG="$ESP/log"
  export DATASETS="rpool rpool/ROOT/arch rpool/var rpool/home"
  export SNAPSHOTS="rpool/ROOT/arch@update-1 rpool/ROOT/arch@update-2
    rpool/var@update-2 rpool/home@manual"
  _run_hook "root=ZFS=rpool/ROOT/arch rw undo_last_update"
  [ "$output" = "$(printf '%s\n' 'zfs rollback -r rpool/ROOT/arch@update-2' \
    'zfs rollback -r rpool/var@update-2')" ]
}

@test "hook: a kept Blank Snapshot becomes @blank again (Impermanence)" {
  export UNDO_CMDLINE="$ESP/cmdline" LOG="$ESP/log"
  export DATASETS="rpool/ROOT/arch rpool/ROOT/etc"
  export SNAPSHOTS="rpool/ROOT/arch@update-2 rpool/ROOT/etc@update-2
    rpool/ROOT/etc@blank"
  _run_hook "root=ZFS=rpool/ROOT/arch undo_last_update"
  [ "$output" = "$(printf '%s\n' 'zfs rollback -r rpool/ROOT/arch@update-2' \
    'zfs rollback -r rpool/ROOT/etc@update-2' \
    'zfs rename rpool/ROOT/etc@update-2 rpool/ROOT/etc@blank')" ]
}

@test "write_initcpio: install + runtime hook in the vendor initcpio dirs" {
  undo_entry_write_initcpio "$ESP/root"
  grep -q add_runscript "$ESP/root/usr/lib/initcpio/install/undo-update"
  grep -q run_latehook "$ESP/root/usr/lib/initcpio/hooks/undo-update"
}

@test "install: runtime, template, initramfs hook and the re-sync unit" {
  local root="$ESP/root"
  undo_entry_install "$root" "$BATS_TEST_DIRNAME/../../lib/boot/undo-entry.sh" \
    systemd-boot linux-lts amd-ucode.img "$CMDLINE" linux-lts
  local lib="$root/usr/local/lib/archzfs"
  [ -x "$lib/undo-entry.sh" ]
  grep -qx "UNDO_LOADER=systemd-boot" "$lib/undo-entry.conf"
  grep -qx "UNDO_KBASE=linux-lts" "$lib/undo-entry.conf"
  grep -q "vmlinuz-linux-lts-prev" "$lib/undo-entry.template"
  [ -f "$root/usr/lib/initcpio/hooks/undo-update" ]
  local units="$root/usr/lib/systemd/system"
  grep -q "ConditionKernelCommandLine=undo_last_update" \
    "$units/undo-last-update-resync.service"
  [ -L "$units/multi-user.target.wants/undo-last-update-resync.service" ]
}

@test "install: rEFInd gets the hide line once" {
  local root="$ESP/root"
  mkdir -p "$root/boot/efi/EFI/refind"
  echo "timeout 5" >"$root/boot/efi/EFI/refind/refind.conf"
  local i
  for i in 1 2; do
    undo_entry_install "$root" \
      "$BATS_TEST_DIRNAME/../../lib/boot/undo-entry.sh" \
      refind linux-lts "" "$CMDLINE" linux-lts linux
  done
  [ "$(grep -c '^dont_scan_files + vmlinuz-linux-lts-prev,vmlinuz-linux-prev$' \
    "$root/boot/efi/EFI/refind/refind.conf")" -eq 1 ]
}

@test "register_efistub: one fixed firmware entry outside BootOrder" {
  local log="$ESP/efibootmgr.log" template="$ESP/template"
  echo "initrd=\\initramfs-linux-lts-prev.img root=x undo_last_update" \
    >"$template"
  efibootmgr() { if (($#)); then echo "$*" >>"$log"; fi; }
  undo_entry_register_efistub /dev/nvme0n1 1 linux-lts "$template"
  grep -q -- "--create-only --disk /dev/nvme0n1 --part 1" "$log"
  grep -q -- "--loader \\\\vmlinuz-linux-lts-prev" "$log"
  # already registered: nothing created again
  efibootmgr() { if (($#)); then echo "$*" >>"$log"; else
    echo "Boot0007* Undo Last Update"; fi; }
  undo_entry_register_efistub /dev/nvme0n1 1 linux-lts "$template"
  [ "$(grep -c -- --create-only "$log")" -eq 1 ]
}

@test "hook: no root=ZFS= on the cmdline means no rollback" {
  export UNDO_CMDLINE="$ESP/cmdline" LOG="$ESP/log"
  export DATASETS="rpool/ROOT/arch" SNAPSHOTS="rpool/ROOT/arch@update-2"
  _run_hook "rw undo_last_update"
  [[ "$output" == "ERR undo-update: no root=ZFS="* ]]
  [[ "$output" != *rollback* ]]
}
