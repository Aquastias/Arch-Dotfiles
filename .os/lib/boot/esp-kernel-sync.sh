#!/usr/bin/env bash
# =============================================================================
# lib/boot/esp-kernel-sync.sh — ESP Kernel Sync (ADR 0038)
# =============================================================================
# systemd-boot cannot read ZFS, so the kernel image, microcode, and initramfs
# must be copied from the ZFS /boot onto the FAT32 ESP. Installed as a pacman
# PostTransaction hook that fires on every kernel transaction.
#
# The set of files to mirror is driven by the loader entries: the planner emits
# exactly the files the entries reference (their linux/initrd lines) that exist
# in /boot. The entries name only Kernel-Selection kernels and the microcode
# present, so a Stray Kernel — having no entry — is never mirrored, and a
# never-referenced file is never copied. This replaces the old linux* glob.
#
# Sourced lib-only by tests (ESP_KERNEL_SYNC_LIB_ONLY=1) to exercise the pure
# planner without the runtime copy loop (mirrors initcpio.sh's lib-only guard).
# =============================================================================

# Pure: print the /boot filenames referenced by the loader entries under
# <esp_dir>/loader/entries that also exist in <boot_dir>, one per line, sorted
# and de-duplicated.
esp_sync_planned_files() {
  local esp_dir="$1" boot_dir="$2" entry name
  for entry in "$esp_dir"/loader/entries/*.conf; do
    [[ -f "$entry" ]] || continue
    awk '$1 == "linux" || $1 == "initrd" { print $2 }' "$entry"
  done | sed 's#^/##' | sort -u | while IFS= read -r name; do
    [[ -n "$name" && -f "$boot_dir/$name" ]] && printf '%s\n' "$name"
  done
}

# Critical files — those an entry references that must land intact or the sync
# fails the transaction (vmlinuz, microcode, the default initramfs): every
# planned file that is not a *fallback* image.
esp_sync_critical_files() {
  esp_sync_planned_files "$1" "$2" | { grep -vF fallback || true; }
}

# Optional files — best-effort extras (the *fallback* initramfs): a failed copy
# warns and is skipped rather than failing the transaction.
esp_sync_optional_files() {
  esp_sync_planned_files "$1" "$2" | { grep -F fallback || true; }
}

# List the orphaned temp files (.*.new) left under <dir> by a prior interrupted
# run, so the next run can sweep them before copying (ADR 0038).
esp_sync_orphan_temps() {
  local dir="$1" f
  for f in "$dir"/.*.new; do
    [[ -f "$f" ]] && printf '%s\n' "$f"
  done
  return 0
}

# Install one critical file: copy to a temp name then rename, so a failed copy
# (e.g. a full ESP) leaves the prior good <dst> intact. Verifies the result
# byte-for-byte against <src>. Returns non-zero on any failure (ADR 0038).
esp_sync_install_critical() {
  local src="$1" dst="$2"
  cp -f "$src" "$dst.new" 2>/dev/null || { rm -f "$dst.new"; return 1; }
  mv -f "$dst.new" "$dst" || { rm -f "$dst.new"; return 1; }
  cmp -s "$src" "$dst"
}

# Estimated bytes the planned files need on an ESP: the sum of their sizes plus
# the largest file again, since temp+rename transiently holds both the old and
# the new copy of the file being written (ADR 0038).
esp_sync_needed_bytes() {
  local esp_dir="$1" boot_dir="$2" f sz total=0 max=0
  while IFS= read -r f; do
    sz=$(stat -c%s "$boot_dir/$f" 2>/dev/null || echo 0)
    total=$((total + sz))
    ((sz > max)) && max=$sz
  done < <(esp_sync_planned_files "$esp_dir" "$boot_dir")
  echo $((total + max))
}

# Bytes the planned files ALREADY occupy on the ESP. A re-sync overwrites these
# in place, so they are not fresh demand on free space — only the transient .new
# of the largest file is. On a populated ESP the prior copies are counted both
# as "used" (hence absent from free) and as "needed"; subtracting them here is
# what stops the preflight false-aborting a re-sync on a small ESP (ADR 0038).
esp_sync_present_bytes() {
  local esp_dir="$1" boot_dir="$2" f sz total=0
  while IFS= read -r f; do
    sz=$(stat -c%s "$esp_dir/$f" 2>/dev/null || echo 0)
    total=$((total + sz))
  done < <(esp_sync_planned_files "$esp_dir" "$boot_dir")
  echo "$total"
}

# True when an ESP with <free_bytes> available can hold the planned files. One
# shared proxy for both the PreTransaction preflight and the PostTransaction
# guard. The prior copies of the planned files (present_bytes) are freed as they
# are overwritten, so they count toward the budget alongside free space.
esp_sync_space_ok() {
  local esp_dir="$1" boot_dir="$2" free="$3" needed present
  needed="$(esp_sync_needed_bytes "$esp_dir" "$boot_dir")"
  present="$(esp_sync_present_bytes "$esp_dir" "$boot_dir")"
  ((free + present >= needed))
}

# True when <dir> is a mount target listed in <mounts_file> (default the live
# /proc/self/mounts). If the ESP is NOT mounted, the sync would copy kernels
# into the ZFS /boot/efi DIRECTORY, leaving the real ESP stale and bricking the
# next boot — the preflight asserts this before any package is touched. Pure +
# testable: tests pass a fixture mounts file (ADR 0038).
esp_sync_is_mountpoint() {
  local dir="${1%/}" mounts="${2:-/proc/self/mounts}"
  [[ -n "$dir" && -r "$mounts" ]] || return 1
  awk -v d="$dir" '$2 == d { f = 1 } END { exit f ? 0 : 1 }' "$mounts"
}

# True when <script> is a well-formed executable: it exists, is executable, and
# begins with a #! shebang. A pacman Exec= runs straight through execv with no
# shell, so a script with no shebang fails ENOEXEC ("Exec format error"); as a
# PostTransaction hook that silently leaves the ESP stale. The preflight
# self-checks this so a malformed sync script aborts the upgrade up front (via
# AbortOnFail) instead of bricking on the next boot (ADR 0038).
esp_sync_script_ok() {
  local script="$1" first
  [[ -f "$script" && -x "$script" ]] || return 1
  IFS= read -r first <"$script" || return 1
  [[ "$first" == '#!'* ]]
}

# Drop any loader entry on <esp_dir> that references a *fallback* initramfs not
# present on that ESP, so an entry never dead-ends on a missing initrd. Always
# returns 0: it is the final action of the sync, and its trailing test must not
# leak as the hook's exit code (a normal run with no dead entry would otherwise
# report failure to pacman). Pure: touches only <esp_dir>; fixture-testable.
esp_sync_prune_dead_fallback_entries() {
  local esp_dir="${1%/}" e ref
  for e in "$esp_dir"/loader/entries/*.conf; do
    [[ -f "$e" ]] || continue
    while IFS= read -r ref; do
      ref="${ref#/}"
      if [[ "$ref" == *fallback* && ! -f "$esp_dir/$ref" ]]; then
        rm -f "$e"
        break
      fi
    done < <(awk '$1 == "initrd" { print $2 }' "$e")
  done
  return 0
}

# Lib-only sourcing for tests: skip the runtime below.
[[ "${ESP_KERNEL_SYNC_LIB_ONLY:-0}" == "1" ]] && return 0

# Runtime: mirror /boot onto every mounted ESP, fail-closed on a critical copy.
# The primary ESP (/boot/efi) holds the loader entries that drive the plan.
_esp_kernel_sync_run() {
  local f d t

  # Refuse to run if any ESP is not mounted: writing into the ZFS /boot/efi
  # DIRECTORY would leave the real ESP stale and brick the next boot. The
  # preflight already asserts this; this is defence-in-depth for a direct or
  # un-preflighted invocation (ADR 0038).
  for d in /boot/efi*/; do
    esp_sync_is_mountpoint "$d" || {
      echo "esp-kernel-sync: FATAL: $d is not a mountpoint — refusing to" \
           "write boot images into the ZFS directory, not the ESP." >&2
      exit 1
    }
  done

  # Sweep orphaned temp files from a prior interrupted run.
  for d in /boot/efi*/; do
    while IFS= read -r t; do rm -f "$t"; done < <(esp_sync_orphan_temps "$d")
  done

  # Critical files MUST land intact on every ESP, or fail the transaction.
  while IFS= read -r f; do
    for d in /boot/efi*/; do
      esp_sync_install_critical "/boot/$f" "${d%/}/$f" || {
        echo "esp-kernel-sync: FATAL: could not write $f to $d (ESP full?) —" \
             "boot images left intact, failing the transaction." >&2
        df -h "$d" >&2
        exit 1
      }
    done
  done < <(esp_sync_critical_files /boot/efi /boot)

  # Optional files (fallback) are best-effort: a failed copy is skipped and any
  # truncated remnant removed, never failing the transaction.
  while IFS= read -r f; do
    for d in /boot/efi*/; do
      cp -f "/boot/$f" "${d%/}/$f" 2>/dev/null || {
        rm -f "${d%/}/$f"
        echo "esp-kernel-sync: WARN: skipped optional $f on $d (no room)." >&2
      }
    done
  done < <(esp_sync_optional_files /boot/efi /boot)

  # Keep fallback boot entries consistent with the fallback image's presence, so
  # an entry never dead-ends on a missing initrd.
  for d in /boot/efi*/; do
    esp_sync_prune_dead_fallback_entries "$d"
  done

  # Explicit success: the pruning helper's trailing test must not become the
  # hook's exit status — a normal run with nothing to prune is not a failure.
  return 0
}

# Preflight (PreTransaction): abort the upgrade early — before any package is
# touched — when the ESP cannot reliably receive the new boot images, so the
# transaction never half-applies into a stale-ESP brick. Three fail-closed
# guards (ADR 0038):
#   1. the shared sync script is a well-formed executable (else execv ENOEXECs
#      at PostTransaction and silently skips the sync);
#   2. every /boot/efi* is actually a mountpoint (else the sync writes into the
#      ZFS directory, not the real ESP);
#   3. every ESP has room for the new images (current sizes as the proxy — the
#      new ones are not built until PostTransaction).
# AbortOnFail propagates any exit 1 here to pacman, which aborts the upgrade.
_esp_kernel_sync_preflight() {
  local d free

  esp_sync_script_ok "$0" || {
    echo "esp-kernel-sync: PRE-TRANSACTION ABORT: sync script '$0' is not a" \
         "well-formed executable (missing #! shebang?). Fix it before" \
         "upgrading, or the ESP would be left stale (ADR 0038)." >&2
    exit 1
  }

  for d in /boot/efi*/; do
    esp_sync_is_mountpoint "$d" || {
      echo "esp-kernel-sync: PRE-TRANSACTION ABORT: $d is not a mountpoint —" \
           "the ESP is not mounted. Mount it before upgrading, or the new" \
           "kernel would not reach the ESP (ADR 0038)." >&2
      exit 1
    }
    free=$(df -B1 --output=avail "$d" 2>/dev/null | tail -1)
    free=${free//[^0-9]/}
    esp_sync_space_ok /boot/efi /boot "${free:-0}" || {
      echo "esp-kernel-sync: PRE-TRANSACTION ABORT: ESP $d lacks room for the" \
           "new boot images. Free space and retry (ADR 0038)." >&2
      df -h "$d" >&2
      exit 1
    }
  done
}

case "${1:-sync}" in
preflight) _esp_kernel_sync_preflight ;;
*)         _esp_kernel_sync_run ;;
esac
