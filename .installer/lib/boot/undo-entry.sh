#!/usr/bin/env bash
# =============================================================================
# lib/boot/undo-entry.sh — the Undo Last Update boot entry (ADR 0166)
# =============================================================================
# One boot entry that boots the Primary Kernel's previous pair (kept on the ESP
# by the ESP Kernel Sync's `previous` mode) with the `undo_last_update`
# parameter, which the initramfs undo-update hook turns into a rollback to the
# newest Update Snapshot.
#
# The entry is rendered once (installer or retrofit, which know the cmdline and
# microcode) into a template, and reconciled at runtime: present while the
# previous pair exists, absent otherwise, so it never dead-ends. efistub is a
# fixed firmware entry written once (a missing file falls through to the next
# entry). rEFInd would autodetect the -prev kernels as plain kernels, booting
# them without the rollback, so they are hidden from its scan.
#
#   reconcile   After the previous pairs change (ESP Kernel Sync `previous`).
#
# Used by: lib/chroot/bootloader-common.sh, lib/chroot/initcpio.sh and
# tools/harden-boot.sh (install), lib/boot/esp-kernel-sync.sh (reconcile).
#
# Sourced lib-only by tests (UNDO_ENTRY_LIB_ONLY=1).
# =============================================================================

UNDO_ENTRY_PARAMETER=undo_last_update   # the cmdline flag asking for Undo
UNDO_ENTRY_TITLE="Undo Last Update"     # the boot-menu label
# marker lines around the Undo block in a shared loader config
_UNDO_ENTRY_BEGIN="# >>> undo-last-update (ADR 0166)"
_UNDO_ENTRY_END="# <<< undo-last-update"
# where the install keeps the runtime, its settings and the template
_UNDO_ENTRY_DIR=/usr/local/lib/archzfs

# Rendering reuses the per-loader renderers; only install and retrofit render,
# so the installed copy runs without them.
# shellcheck source=./loader-entries.sh
declare -F loader_entries_systemd_boot >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/loader-entries.sh" 2>/dev/null || true

# undo_entry_render <loader> <kbase> <microcode-imgs> <cmdline> — the Undo
# entry for <loader>: <kbase>'s previous pair, microcode first, <cmdline> plus
# the undo parameter. efistub prints its firmware load options.
undo_entry_render() {
  local loader="$1" base="$2" microcode="$3" cmdline="$4 $UNDO_ENTRY_PARAMETER"
  local initrd="initramfs-$base-prev.img" image initrds=""
  # One "initrd  /<image>" line per microcode image.
  initrds="$(for image in $microcode; do printf 'initrd  /%s\n' "$image"; done)"
  case "$loader" in
  systemd-boot)
    loader_entries_systemd_boot "$UNDO_ENTRY_TITLE" "$base-prev" \
      "$initrds" "$initrd" "$cmdline"
    ;;
  limine)
    loader_entries_limine "$UNDO_ENTRY_TITLE" "$base-prev" \
      "$initrds" "$initrd" "$cmdline"
    ;;
  grub)
    loader_entries_grub "$UNDO_ENTRY_TITLE" "$base-prev" "$microcode" \
      "$initrd" "$cmdline"
    ;;
  refind)
    # rEFInd appends the stanza's initrd; extra ones go in options.
    printf 'menuentry "%s" {\n' "$UNDO_ENTRY_TITLE"
    printf '    loader  /vmlinuz-%s-prev\n' "$base"
    printf '    initrd  /%s\n' "$initrd"
    initrds=""
    for image in $microcode; do initrds+="initrd=\\$image "; done
    printf '    options "%s%s"\n' "$initrds" "$cmdline"
    printf '}\n'
    ;;
  efistub)
    loader_entries_efistub_options "$initrd" "$microcode" "$cmdline"
    ;;
  esac
}

# undo_entry_refind_hide <kbase>… — the refind.conf line keeping every
# previous kernel out of rEFInd's autodetection (added to its defaults).
undo_entry_refind_hide() {
  local base files=""
  for base in "$@"; do files+="${files:+,}vmlinuz-$base-prev"; done
  printf 'dont_scan_files + %s\n' "$files"
}

# _undo_entry_strip <file> — remove the marked Undo block from <file>.
_undo_entry_strip() {
  [[ -f "$1" ]] || return 0
  local line skipping=0
  # Every line outside the begin…end markers (the markers dropped too).
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$_UNDO_ENTRY_BEGIN" ]]; then skipping=1; continue; fi
    if [[ "$line" == "$_UNDO_ENTRY_END" ]]; then skipping=0; continue; fi
    (( skipping )) || printf '%s\n' "$line"
  done < "$1" > "$1.new"
  mv -f "$1.new" "$1"
}

# undo_entry_reconcile <esp> <loader> <kbase> <template> — make the Undo entry
# present exactly while <kbase>'s previous pair is on <esp>.
undo_entry_reconcile() {
  local esp="$1" loader="$2" base="$3" template="$4" config present=0
  [[ -f "$esp/vmlinuz-$base-prev" && -f "$esp/initramfs-$base-prev.img" ]] \
    && present=1
  case "$loader" in
  systemd-boot)
    config="$esp/loader/entries/arch-undo.conf"
    if ((present)); then cp -f "$template" "$config"; else rm -f "$config"; fi
    return 0
    ;;
  limine) config="$esp/limine.conf" ;;
  grub) config="$esp/grub/grub.cfg" ;;
  refind) config="$esp/EFI/refind/refind.conf" ;;
  *) return 0 ;;
  esac
  [[ -f "$config" ]] || return 0
  _undo_entry_strip "$config"
  if ((present)); then
    { printf '%s\n' "$_UNDO_ENTRY_BEGIN"; cat "$template"
      printf '%s\n' "$_UNDO_ENTRY_END"; } >>"$config"
  fi
  return 0
}

# undo_entry_initcpio_install / undo_entry_initcpio_hook — the mkinitcpio
# undo-update hook, run as a latehook right after the zfs hook imported and
# unlocked the pool and mounted the root, before zfs-rollback. With
# undo_last_update on the cmdline it rolls every dataset holding the newest
# Update Snapshot back to it (-r: newer snapshots go). A Rollback Dataset's
# copy is its kept pre-update Blank Snapshot, so it becomes @blank again for
# zfs-rollback to apply. The root dataset comes from root=ZFS= on the cmdline,
# not the mount table (the initramfs mounts it at /sysroot, not /new_root).
# UNDO_CMDLINE is the test seam.
undo_entry_initcpio_install() {
  cat <<'INSTALL'
#!/usr/bin/env bash
build() {
  add_runscript
}
help() {
  echo "Undo Last Update: roll back to the newest Update Snapshot (ADR 0166)."
}
INSTALL
}

undo_entry_initcpio_hook() {
  cat <<'HOOK'
#!/usr/bin/ash
run_latehook() {
  local cmdline="${UNDO_CMDLINE:-/proc/cmdline}" root pool name ds arg
  # The literal mirrors UNDO_ENTRY_PARAMETER: this runs in the busybox
  # initramfs, where the lib is not available.
  case " $(cat "$cmdline") " in
  *" undo_last_update "*) ;;
  *) return 0 ;;
  esac
  # Builtins only: this busybox has no tr.
  root=""
  for arg in $(cat "$cmdline"); do
    case "$arg" in root=ZFS=*) root="${arg#root=ZFS=}" ;; esac
  done
  if [ -z "$root" ]; then
    err "undo-update: no root=ZFS= on the cmdline"
    return 0
  fi
  pool="${root%%/*}"
  name="$(zfs list -H -t snapshot -o name -r "$pool" \
    | awk -F@ '$2 ~ /^update-/ { print $2 }' | sort \
    | awk 'END { if (NR) print }')"
  if [ -z "$name" ]; then
    err "undo-update: no Update Snapshot on $pool"
    return 0
  fi
  for ds in $(zfs list -H -o name -r "$pool"); do
    zfs list -H "$ds@$name" >/dev/null 2>&1 || continue
    if zfs list -H "$ds@blank" >/dev/null 2>&1; then
      zfs rollback -r "$ds@$name" && zfs rename "$ds@$name" "$ds@blank"
    else
      zfs rollback -r "$ds@$name"
    fi
  done
  msg "undo-update: rolled back to @$name"
}
HOOK
}

# undo_entry_write_initcpio <root> — write the hook pair into the vendor
# initcpio dirs under <root> (never /etc, which Impermanence rolls back).
undo_entry_write_initcpio() {
  local root="$1"
  mkdir -p "$root/usr/lib/initcpio/install" "$root/usr/lib/initcpio/hooks"
  undo_entry_initcpio_install >"$root/usr/lib/initcpio/install/undo-update"
  undo_entry_initcpio_hook >"$root/usr/lib/initcpio/hooks/undo-update"
}

# undo_entry_resync_unit — after an Undo boot the root holds the old kernel's
# modules but the ESP's default pair is still the new kernel; re-sync the ESP
# from the rolled-back /boot so the next normal boot matches.
undo_entry_resync_unit() {
  cat <<UNIT
[Unit]
Description=Re-sync the ESP with the system Undo Last Update restored
ConditionKernelCommandLine=$UNDO_ENTRY_PARAMETER
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/lib/archzfs/esp-kernel-sync.sh

[Install]
WantedBy=multi-user.target
UNIT
}

# undo_entry_install <root> <source-script> <loader> <primary-kbase>
#                    <microcode-imgs> <cmdline> <kbase>… — install the runtime,
# its settings and rendered template, the initramfs hook and the enabled
# re-sync unit under <root>; on rEFInd, hide every <kbase>'s previous kernel
# from autodetection. The one install path for the installer and the retrofit.
# Units are enabled from the vendor .wants dir, never /etc.
undo_entry_install() {
  local root="$1" source_script="$2" loader="$3" base="$4"
  local microcode="$5" cmdline="$6"
  shift 6
  local lib="$root/usr/local/lib/archzfs" units="$root/usr/lib/systemd/system"
  local refind="$root/boot/efi/EFI/refind/refind.conf" hide
  install -Dm755 "$source_script" "$lib/undo-entry.sh"
  printf 'UNDO_LOADER=%s\nUNDO_KBASE=%s\n' "$loader" "$base" \
    >"$lib/undo-entry.conf"
  undo_entry_render "$loader" "$base" "$microcode" "$cmdline" \
    >"$lib/undo-entry.template"
  undo_entry_write_initcpio "$root"
  mkdir -p "$units/multi-user.target.wants"
  undo_entry_resync_unit >"$units/undo-last-update-resync.service"
  ln -sfn ../undo-last-update-resync.service \
    "$units/multi-user.target.wants/undo-last-update-resync.service"
  if [[ "$loader" == refind && -f "$refind" ]]; then
    hide="$(undo_entry_refind_hide "$@")"
    grep -qxF "$hide" "$refind" || printf '%s\n' "$hide" >>"$refind"
  fi
  return 0
}

# undo_entry_register_efistub <disk> <part> <kbase> <template> — efistub's
# fixed firmware entry booting <kbase>'s previous pair with the load options
# in <template>. --create-only keeps it out of BootOrder, so it never becomes
# the default; an existing entry is left alone.
undo_entry_register_efistub() {
  local disk="$1" part="$2" base="$3" template="$4"
  efibootmgr | grep -qF "$UNDO_ENTRY_TITLE" && return 0
  efibootmgr --create-only --disk "$disk" --part "$part" \
    --label "$UNDO_ENTRY_TITLE" --loader "\\vmlinuz-$base-prev" \
    --unicode "$(<"$template")"
}

# Lib-only sourcing for tests: skip the runtime below.
[[ "${UNDO_ENTRY_LIB_ONLY:-0}" == "1" ]] && return 0

# Runtime: the install wrote the loader and Primary Kernel to undo-entry.conf
# and the rendered entry to undo-entry.template.
case "${1:-}" in
reconcile)
  [[ -f "$_UNDO_ENTRY_DIR/undo-entry.conf" ]] || exit 0
  # shellcheck source=/dev/null
  source "$_UNDO_ENTRY_DIR/undo-entry.conf"
  # Every ESP: secondaries carry their own copy of the loader config.
  for _esp in /boot/efi*/; do
    undo_entry_reconcile "$_esp" "${UNDO_LOADER:-}" "${UNDO_KBASE:-}" \
      "$_UNDO_ENTRY_DIR/undo-entry.template"
  done
  ;;
*)
  echo "usage: undo-entry.sh reconcile" >&2
  exit 2
  ;;
esac
