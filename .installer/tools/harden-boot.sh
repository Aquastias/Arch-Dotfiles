#!/usr/bin/env bash
# =============================================================================
# tools/harden-boot.sh — boot-resilience retrofit for a running system (ADR 0038)
# =============================================================================
# Brings an already-installed machine up to the hardened boot standard without a
# reinstall and without repartitioning. Idempotent; --dry-run previews.
#
#   systemd-boot host: install the hardened ESP Kernel Sync (+ preflight) and the
#                      Stray Kernel warn hook from the shared lib/boot artifacts,
#                      reconcile loader entries to present microcode, and drop the
#                      fallback when the ESP is under the 1G floor.
#   grub host:         pin the Primary Kernel as default + install the warn hook.
#
# Installs the SAME shared artifacts the installer stages (single source, ADR
# 0023). Pure planner helpers are lib-only-sourceable (HARDEN_BOOT_LIB_ONLY=1).
# =============================================================================

# Repo .os dir, resolved from this script's location (tools/ -> .os/).
_HB_OS_DIR="$(cd "${BASH_SOURCE[0]%/*}/.." 2>/dev/null && pwd || true)"

# Detect the bootloader under <root>: "systemd-boot" if the ESP carries a
# loader/entries dir, "grub" if /boot/grub exists, else "" (unknown).
harden_boot_detect_bootloader() {
  local root="${1:-}"
  if [[ -d "$root/boot/efi/loader/entries" ]]; then
    echo systemd-boot
  elif [[ -d "$root/boot/grub" ]]; then
    echo grub
  else
    echo ""
  fi
}

# True when an ESP of <esp_mib> is below the 1G floor and should not carry the
# fallback initramfs (retrofit on a small, e.g. 512M, ESP).
harden_boot_should_drop_fallback() {
  ((${1:-0} < 1024))
}

# Emit the planned retrofit actions for <bootloader> on an ESP of <esp_mib>, one
# action token per line. Drives both --dry-run (printed) and apply (executed).
harden_boot_plan() {
  local bl="$1" esp_mib="$2"
  case "$bl" in
  systemd-boot)
    echo install-esp-kernel-sync
    echo install-warn-hook
    echo reconcile-microcode
    harden_boot_should_drop_fallback "$esp_mib" && echo drop-fallback
    ;;
  grub)
    echo pin-grub-default
    echo install-warn-hook
    ;;
  esac
  return 0
}

# Lib-only sourcing for tests: skip the apply/runtime below.
[[ "${HARDEN_BOOT_LIB_ONLY:-0}" == "1" ]] && return 0

set -Eeuo pipefail

# ── apply helpers ─────────────────────────────────────────────────────────────
# Selected kernel bases for the warn hook: derive from what the system is set to
# boot — the loader entries' vmlinuz (systemd-boot) or GRUB_TOP_LEVEL (grub).
_hb_selected_kernels() {
  local f
  for f in "$ESP"/loader/entries/*.conf; do
    [[ -f "$f" ]] || continue
    awk '$1 == "linux" { print $2 }' "$f"
  done 2>/dev/null | sed 's#.*/vmlinuz-##' | sort -u
  [[ -f "$ROOT/etc/default/grub" ]] &&
    sed -n 's/.*GRUB_TOP_LEVEL="\/boot\/vmlinuz-\(.*\)".*/\1/p' \
      "$ROOT/etc/default/grub"
}

_hb_write_hook() { # _hb_write_hook <name> <when> <exec> <desc>
  mkdir -p "$ROOT/etc/pacman.d/hooks"
  cat >"$ROOT/etc/pacman.d/hooks/$1" <<HOOK
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/lib/modules/*/vmlinuz

[Action]
Description = $4
When = $2
Exec = $3
${5:-}
HOOK
}

_hb_install_esp_kernel_sync() {
  install -Dm755 "$_HB_OS_DIR/lib/boot/esp-kernel-sync.sh" \
    "$ROOT/usr/local/lib/archzfs/esp-kernel-sync.sh"
  _hb_write_hook 93-esp-kernel-sync-preflight.hook PreTransaction \
    "/usr/local/lib/archzfs/esp-kernel-sync.sh preflight" \
    "Checking ESP free space for new boot images..." "AbortOnFail"
  _hb_write_hook 94-esp-kernel-sync.hook PostTransaction \
    "/usr/local/lib/archzfs/esp-kernel-sync.sh" \
    "Syncing kernel and initramfs to ESP..."
}

_hb_install_warn_hook() {
  install -Dm755 "$_HB_OS_DIR/lib/boot/stray-kernel.sh" \
    "$ROOT/usr/local/lib/archzfs/stray-kernel.sh"
  install -Dm644 "$_HB_OS_DIR/lib/zfs/verify.sh" \
    "$ROOT/usr/local/lib/archzfs/verify.sh"
  _hb_selected_kernels >"$ROOT/usr/local/lib/archzfs/selected-kernels"
  _hb_write_hook 97-stray-kernel-warn.hook PostTransaction \
    "/usr/local/lib/archzfs/stray-kernel.sh warn" \
    "Checking for stray / zfs.ko-less kernels..."
}

# Drop initrd lines for *-ucode.img absent from the ESP, so no entry dangles.
_hb_reconcile_microcode() {
  local e
  for e in "$ESP"/loader/entries/*.conf; do
    [[ -f "$e" ]] || continue
    awk -v esp="$ESP" '
      $1 == "initrd" {
        f = $2; sub(/^\//, "", f)
        if (f ~ /-ucode\.img$/ &&
            system("test -f \"" esp "/" f "\"") != 0) next
      }
      { print }
    ' "$e" >"$e.tmp" && mv "$e.tmp" "$e"
  done
}

_hb_drop_fallback() {
  rm -f "$ESP"/initramfs-*-fallback.img
  local e
  for e in "$ESP"/loader/entries/*.conf; do
    [[ -f "$e" ]] || continue
    grep -q 'fallback' "$e" && rm -f "$e"
  done
}

_hb_pin_grub_default() {
  # shellcheck source=../lib/grub-common.sh
  source "$_HB_OS_DIR/lib/grub-common.sh"
  local pool_root primary_base primary_vmlinuz=""
  pool_root="$(findmnt -n -o SOURCE "$ROOT" 2>/dev/null || true)"
  # Prefer linux-lts when present, else the first installed kernel's pkgbase.
  primary_base="$(
    for m in "$ROOT"/usr/lib/modules/*/pkgbase; do
      [[ -f "$m" ]] && cat "$m"
    done 2>/dev/null | sort | grep -m1 -x linux-lts ||
      for m in "$ROOT"/usr/lib/modules/*/pkgbase; do
        [[ -f "$m" ]] && {
          cat "$m"
          break
        }
      done 2>/dev/null
  )"
  [[ -n "$primary_base" ]] && primary_vmlinuz="/boot/vmlinuz-${primary_base}"
  _grub_default_config "$pool_root" "$primary_vmlinuz" \
    >"$ROOT/etc/default/grub"
  ZPOOL_VDEV_NAME_PATH=YES grub-mkconfig -o "$ROOT/boot/grub/grub.cfg"
}

# ── main ──────────────────────────────────────────────────────────────────────
DRY=0
ROOT=/
while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run) DRY=1 ;;
  --root)
    ROOT="$2"
    shift
    ;;
  -h | --help)
    echo "usage: harden-boot.sh [--dry-run] [--root DIR]"
    exit 0
    ;;
  *)
    echo "harden-boot: unknown arg '$1'" >&2
    exit 2
    ;;
  esac
  shift
done
ROOT="${ROOT%/}"
[[ -z "$ROOT" ]] && ROOT=""
ESP="$ROOT/boot/efi"

[[ -n "$_HB_OS_DIR" ]] || {
  echo "harden-boot: cannot locate the repo .os dir" >&2
  exit 1
}

bl="$(harden_boot_detect_bootloader "${ROOT:-/}")"
[[ -n "$bl" ]] || {
  echo "harden-boot: could not detect a bootloader under ${ROOT:-/}" >&2
  exit 1
}

esp_mib=0
if [[ -d "$ESP" ]]; then
  esp_mib="$(df -BM --output=size "$ESP" 2>/dev/null | tail -1 | tr -dc '0-9')"
fi
esp_mib="${esp_mib:-0}"

echo "harden-boot: bootloader=$bl ESP=${esp_mib}MiB root=${ROOT:-/}$(
  ((DRY)) && echo ' (dry-run)'
)"

while IFS= read -r action; do
  if ((DRY)); then
    echo "  would: $action"
    continue
  fi
  echo "  applying: $action"
  case "$action" in
  install-esp-kernel-sync) _hb_install_esp_kernel_sync ;;
  install-warn-hook) _hb_install_warn_hook ;;
  reconcile-microcode) _hb_reconcile_microcode ;;
  drop-fallback) _hb_drop_fallback ;;
  pin-grub-default) _hb_pin_grub_default ;;
  esac
done < <(harden_boot_plan "$bl" "$esp_mib")

echo "harden-boot: done."
