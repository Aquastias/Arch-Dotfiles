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
#   battery  PreTransaction (kernel paths, AbortOnFail): refuse a kernel
#            transaction on a discharging battery below 30%.
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

# Lib-only sourcing for tests: skip the runtime below.
[[ "${BOOT_RECOVERY_LIB_ONLY:-0}" == "1" ]] && return 0

case "${1:-}" in
battery) boot_recovery_battery_ok >&2 ;;
*)
  echo "usage: boot-recovery.sh battery" >&2
  exit 2
  ;;
esac
