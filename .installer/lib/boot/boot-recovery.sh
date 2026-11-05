#!/usr/bin/env bash
# =============================================================================
# lib/boot/boot-recovery.sh — interrupted-update recovery (ADR 0166)
# =============================================================================
# A kernel upgrade removes the old kernel's modules before its PostTransaction
# hooks rebuild the initramfs and the ESP Kernel Sync mirrors the new kernel.
# Cut off in between (an Interrupted Kernel Transaction), the ESP still boots
# the old kernel with no modules on disk. This module keeps that window
# survivable. Installed to /usr/local/lib/archzfs/ and run from pacman hooks:
#
#   battery     PreTransaction (kernel paths, AbortOnFail): refuse a kernel
#               transaction on a discharging battery below 30%.
#   stash       PreTransaction (kernel paths), before the dkms hooks: the Module
#               Stash — a hard-linked copy of every selected kernel's modules
#               under /usr/lib/modules/.stash (free, and on the root dataset,
#               which is mounted before any module loads).
#   restore     Early boot unit: the Stash Restore, when the running kernel has
#               no modules on disk.
#   drop-stash  Called by the ESP Kernel Sync once the new kernel is on the ESP.
#
# Sourced lib-only by tests (BOOT_RECOVERY_LIB_ONLY=1); every decision takes
# its fixture dirs as arguments, so bats never touches the live system.
# =============================================================================

_BOOT_RECOVERY_MIN_BATTERY=30

# boot_recovery_battery_ok [power-supply-dir] — 0 when a kernel transaction may
# run: no battery, a charger online, a battery charging, or the batteries'
# average capacity at or above 30%. Otherwise prints why and returns 1.
boot_recovery_battery_ok() {
  local supply_directory="${1:-/sys/class/power_supply}" supply type
  local batteries=0 total=0 status
  for supply in "$supply_directory"/*/; do
    type="$(cat "$supply/type" 2>/dev/null || true)"
    case "$type" in
    Mains | USB)
      [[ "$(cat "$supply/online" 2>/dev/null || true)" == 1 ]] && return 0
      ;;
    Battery)
      status="$(cat "$supply/status" 2>/dev/null || true)"
      [[ "$status" == Charging ]] && return 0
      batteries=$((batteries + 1))
      total=$((total + $(cat "$supply/capacity" 2>/dev/null || echo 0)))
      ;;
    esac
  done
  ((batteries == 0)) && return 0
  ((total / batteries >= _BOOT_RECOVERY_MIN_BATTERY)) && return 0
  echo "boot-recovery: battery at $((total / batteries))% and not charging —" \
       "plug in the charger before a kernel update (ADR 0166)."
  return 1
}

# boot_recovery_battery_hook — the pacman hook running the battery check before
# any kernel transaction. Single source for the installer and the retrofit.
boot_recovery_battery_hook() {
  cat <<'HOOK'
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/lib/modules/*/vmlinuz

[Action]
Description = Checking the battery before a kernel update...
When = PreTransaction
Exec = /usr/local/lib/archzfs/boot-recovery.sh battery
AbortOnFail
HOOK
}

# boot_recovery_stash_plan <modules-dir> <selected-pkgbase>… — the module trees
# to stash: every installed kernel whose pkgbase is in the Kernel Selection.
# Stray Kernels never reach the ESP, so they are never stashed.
boot_recovery_stash_plan() {
  local modules_directory="$1" marker
  shift
  local -A selected=()
  local base
  for base in "$@"; do selected["$base"]=1; done
  for marker in "$modules_directory"/*/pkgbase; do
    [[ -f "$marker" ]] || continue
    base="$(<"$marker")"
    if [[ -n "${selected[$base]:-}" ]]; then
      marker="${marker%/pkgbase}"
      printf '%s\n' "${marker##*/}"
    fi
  done
}

# boot_recovery_stash <modules-dir> <selected-pkgbase>… — replace the Module
# Stash with hard-linked copies of the planned trees. pacman and dkms unlink
# files rather than rewrite them, so the stashed inodes outlive their removal.
boot_recovery_stash() {
  local modules_directory="$1" stash="$1/.stash" version restored=""
  shift
  # A pending Stash Restore record outlives the re-stash: drop_stash still
  # needs it to clean up the restored tree once the update finally completes.
  [[ -f "$stash/restored" ]] && restored="$(<"$stash/restored")"
  rm -rf "$stash"
  mkdir -p "$stash"
  [[ -n "$restored" ]] && printf '%s\n' "$restored" >"$stash/restored"
  while IFS= read -r version; do
    cp -al "$modules_directory/$version" "$stash/$version"
  done < <(boot_recovery_stash_plan "$modules_directory" "$@")
}

# boot_recovery_should_restore <modules-dir> <release> — 0 when the running
# kernel <release> has no modules on disk but a Module Stash holds them.
boot_recovery_should_restore() {
  [[ ! -d "$1/$2" && -d "$1/.stash/$2" ]]
}

# boot_recovery_restore <modules-dir> <release> — the Stash Restore: link the
# stashed tree back and record "<release> <pkgbase>" for the notice and for
# drop_stash.
boot_recovery_restore() {
  local modules_directory="$1" release="$2" stash="$1/.stash"
  boot_recovery_should_restore "$modules_directory" "$release" || return 0
  cp -al "$stash/$release" "$modules_directory/$release"
  printf '%s %s\n' "$release" \
    "$(cat "$modules_directory/$release/pkgbase" 2>/dev/null || true)" \
    >>"$stash/restored"
}

# boot_recovery_owned <file> — 0 when a package owns <file>. Tests override it.
boot_recovery_owned() {
  pacman -Qqo "$1" >/dev/null 2>&1
}

# boot_recovery_drop_stash <modules-dir> — once the new kernel is on the ESP:
# remove each restored tree no package owns any more, then the stash.
boot_recovery_drop_stash() {
  local modules_directory="$1" stash="$1/.stash" release _
  if [[ -f "$stash/restored" ]]; then
    while read -r release _; do
      [[ -n "$release" ]] || continue
      boot_recovery_owned "$modules_directory/$release/vmlinuz" \
        || rm -rf "${modules_directory:?}/$release"
    done <"$stash/restored"
  fi
  rm -rf "$stash"
}

# boot_recovery_stash_hook — the pacman hook taking the Module Stash before any
# kernel transaction. Named 05- so it runs before the dkms removal hooks (7x).
boot_recovery_stash_hook() {
  cat <<'HOOK'
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Operation = Remove
Target = usr/lib/modules/*/vmlinuz

[Action]
Description = Keeping the current kernel modules (Module Stash)...
When = PreTransaction
Exec = /usr/local/lib/archzfs/boot-recovery.sh stash
HOOK
}

# boot_recovery_restore_unit — the Stash Restore unit. %v is the running kernel
# release; it runs only when that kernel has no modules but a stash does, and
# before anything (systemd-modules-load, udev) loads a module.
boot_recovery_restore_unit() {
  cat <<'UNIT'
[Unit]
Description=Restore kernel modules kept before an interrupted update
Documentation=file:///usr/local/lib/archzfs/boot-recovery.sh
DefaultDependencies=no
After=systemd-remount-fs.service
Before=systemd-modules-load.service systemd-udevd.service sysinit.target
ConditionPathExists=!/usr/lib/modules/%v
ConditionPathExists=/usr/lib/modules/.stash/%v

[Service]
Type=oneshot
ExecStart=/usr/local/lib/archzfs/boot-recovery.sh restore
StandardOutput=journal+console

[Install]
WantedBy=sysinit.target
UNIT
}

# boot_recovery_notice <modules-dir> — the interruption notice while a Stash
# Restore is pending: what happened and the one command that finishes the
# update (re-installing the kernel package(s) re-runs the hooks it missed;
# `pacman -Syu` alone would find nothing to do). Empty when nothing was
# restored.
boot_recovery_notice() {
  local restored="$1/.stash/restored" packages
  [[ -s "$restored" ]] || return 0
  packages="$(awk 'NF > 1 && !seen[$2]++ {
      printf "%s%s", sep, $2; sep = " " }' \
    "$restored")"
  echo "The last kernel update was interrupted; the previous kernel's" \
       "modules were restored so this boot could finish. Run:" \
       "sudo pacman -S ${packages:-<your kernel>}"
}

# boot_recovery_notice_unit — the user unit showing the notice as a desktop
# notification after login, every login until the update is finished.
boot_recovery_notice_unit() {
  cat <<'UNIT'
[Unit]
Description=Tell the user an interrupted kernel update needs finishing
ConditionPathExists=/usr/lib/modules/.stash/restored
ConditionPathExists=/usr/bin/gdbus

[Service]
Type=oneshot
ExecStart=/usr/local/lib/archzfs/boot-recovery.sh notify

[Install]
WantedBy=default.target
UNIT
}

# boot_recovery_install <root> <source-script> — install this helper, its
# pacman hooks, the Stash Restore unit and the notice user unit under <root>
# ("" = /). The one install path for the installer and the retrofit tool. Both
# units are enabled from the vendor .wants dirs, never /etc, which Impermanence
# rolls back at boot.
boot_recovery_install() {
  local root="${1%/}" source_script="$2"
  local hooks="$root/etc/pacman.d/hooks" units="$root/usr/lib/systemd/system"
  local user_units="$root/usr/lib/systemd/user"
  install -Dm755 "$source_script" "$root/usr/local/lib/archzfs/boot-recovery.sh"
  mkdir -p "$hooks" "$units/sysinit.target.wants" \
    "$user_units/default.target.wants"
  boot_recovery_battery_hook >"$hooks/92-battery-preflight.hook"
  boot_recovery_stash_hook >"$hooks/05-module-stash.hook"
  boot_recovery_restore_unit >"$units/boot-recovery-restore.service"
  ln -sfn ../boot-recovery-restore.service \
    "$units/sysinit.target.wants/boot-recovery-restore.service"
  boot_recovery_notice_unit >"$user_units/boot-recovery-notice.service"
  ln -sfn ../boot-recovery-notice.service \
    "$user_units/default.target.wants/boot-recovery-notice.service"
}

# Lib-only sourcing for tests: skip the runtime below.
[[ "${BOOT_RECOVERY_LIB_ONLY:-0}" == "1" ]] && return 0

_BOOT_RECOVERY_MODULES=/usr/lib/modules
_BOOT_RECOVERY_SELECTED=/usr/local/lib/archzfs/selected-kernels

# The Kernel Selection's package bases; every installed kernel's when the list
# is missing (a stash too many costs nothing — it is hard links).
_boot_recovery_selected() {
  if [[ -s "$_BOOT_RECOVERY_SELECTED" ]]; then
    cat "$_BOOT_RECOVERY_SELECTED"
  else
    cat "$_BOOT_RECOVERY_MODULES"/*/pkgbase 2>/dev/null | sort -u
  fi
}

# Desktop notification through the session bus (glib2's gdbus, so no libnotify
# dependency). Waits for a notification server, which a session starts after
# the user manager.
_boot_recovery_notify() {
  local message
  message="$(boot_recovery_notice "$_BOOT_RECOVERY_MODULES")"
  [[ -n "$message" ]] || return 0
  gdbus wait --session --timeout 300 org.freedesktop.Notifications || return 0
  gdbus call --session --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.Notify \
    "Kernel update" 0 dialog-warning "Kernel update interrupted" \
    "$message" '[]' '{"urgency": <byte 2>}' 0 >/dev/null
}

case "${1:-}" in
battery) boot_recovery_battery_ok >&2 ;;
stash)
  mapfile -t _selected < <(_boot_recovery_selected)
  boot_recovery_stash "$_BOOT_RECOVERY_MODULES" \
    "${_selected[@]+"${_selected[@]}"}" \
    || echo "boot-recovery: WARN: could not take the Module Stash." >&2
  exit 0
  ;;
restore)
  boot_recovery_restore "$_BOOT_RECOVERY_MODULES" "$(uname -r)"
  boot_recovery_notice "$_BOOT_RECOVERY_MODULES"
  ;;
drop-stash) boot_recovery_drop_stash "$_BOOT_RECOVERY_MODULES" ;;
notify) _boot_recovery_notify ;;
*)
  echo "usage: boot-recovery.sh" \
    "battery | stash | restore | drop-stash | notify" >&2
  exit 2
  ;;
esac
