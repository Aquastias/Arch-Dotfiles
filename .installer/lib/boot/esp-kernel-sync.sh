#!/usr/bin/env bash
# =============================================================================
# lib/boot/esp-kernel-sync.sh — ESP Kernel Sync (ADR 0038)
# =============================================================================
# systemd-boot cannot read ZFS, so the kernel image, microcode, and initramfs
# must be copied from the ZFS /boot onto the FAT32 ESP. Installed as a pacman
# PostTransaction hook after every transaction (an initramfs rebuilt without a
# kernel change must reach the ESP too); unchanged files are skipped. A
# `previous` mode, run before every transaction, keeps each kernel's prior pair
# for Undo Last Update (ADR 0166).
#
# The set of files to mirror is the Kernel-Selection boot images already on
# the ESP: the files the systemd-boot loader entries reference (their
# linux/initrd lines) plus the vmlinuz-*/initramfs-*/*-ucode images staged at
# the ESP root — how GRUB, Limine, rEFInd and EFISTUB keep theirs (no entries
# there). Only those that also exist in /boot are planned, so a Stray Kernel —
# never staged on the ESP — is never mirrored, and nothing else is copied.
#
# Sourced lib-only by tests (ESP_KERNEL_SYNC_LIB_ONLY=1) to exercise the pure
# planner without the runtime copy loop (mirrors initcpio.sh's lib-only guard).
# =============================================================================

# esp_kernel_sync_without_slash <path> — <path> with one trailing "/"
# dropped ("/boot/efi/" → "/boot/efi").
esp_kernel_sync_without_slash() {
  local path="$1"
  if [[ "$path" == */ ]]; then
    # Every character but the last.
    path="$(printf '%s\n' "$path" | cut -c"1-$(( ${#path} - 1 ))")"
  fi
  printf '%s\n' "$path"
}

# esp_kernel_sync_entry_files <entry> <key>... — the file named on each
# "<key> <path>" line of a loader entry (`linux`, `initrd`), without its
# leading "/". (The `|| -n` keeps a last line that has no newline.)
esp_kernel_sync_entry_files() {
  local entry="$1" key path _rest wanted
  shift
  while read -r key path _rest || [[ -n "$key" ]]; do
    for wanted in "$@"; do
      [[ "$key" == "$wanted" ]] || continue
      # The path without its leading "/".
      [[ "$path" == /* ]] && path="$(printf '%s\n' "$path" | cut -c2-)"
      printf '%s\n' "$path"
    done
  done < "$entry"
}

# esp_kernel_sync_esp_files <esp_dir> — every boot file <esp_dir> uses: the
# files its loader entries reference, then the boot images staged at its
# root. One per line, unsorted, maybe repeated.
esp_kernel_sync_esp_files() {
  local esp_directory="$1" entry staged
  for entry in "$esp_directory"/loader/entries/*.conf; do
    [[ -f "$entry" ]] || continue
    esp_kernel_sync_entry_files "$entry" linux initrd
  done
  for staged in "$esp_directory"/vmlinuz-* "$esp_directory"/initramfs-*.img \
                "$esp_directory"/*-ucode.img; do
    [[ -f "$staged" ]] || continue
    basename "$staged"
  done
}

# Pure: print the /boot filenames to mirror onto <esp_dir> — those its loader
# entries reference plus the boot images staged at its root — that also exist
# in <boot_dir>, one per line, sorted and de-duplicated.
esp_kernel_sync_planned_files() {
  local esp_directory="$1" boot_directory="$2" name
  local -a names
  # The ESP's boot files, sorted, each once.
  mapfile -t names < <(esp_kernel_sync_esp_files "$esp_directory" | sort -u)
  for name in "${names[@]}"; do
    [[ -n "$name" && -f "$boot_directory/$name" ]] && printf '%s\n' "$name"
  done
  return 0
}

# Critical files — those an entry references that must land intact or the sync
# fails the transaction (vmlinuz, microcode, the default initramfs): every
# planned file that is not a *fallback* image.
esp_kernel_sync_critical_files() {
  esp_kernel_sync_planned_files "$1" "$2" | { grep -vF fallback || true; }
}

# Optional files — best-effort extras (the *fallback* initramfs): a failed copy
# warns and is skipped rather than failing the transaction.
esp_kernel_sync_optional_files() {
  esp_kernel_sync_planned_files "$1" "$2" | { grep -F fallback || true; }
}

# List the orphaned temp files (.*.new) left under <dir> by a prior interrupted
# run, so the next run can sweep them before copying (ADR 0038).
esp_kernel_sync_orphan_temporaries() {
  local directory="$1" file
  for file in "$directory"/.*.new; do
    [[ -f "$file" ]] && printf '%s\n' "$file"
  done
  return 0
}

# Install one critical file: copy to a temp name then rename, so a failed copy
# (e.g. a full ESP) leaves the prior good <dst> intact. Verifies the result
# byte-for-byte against <src>. Returns non-zero on any failure (ADR 0038).
esp_kernel_sync_install_critical() {
  local source_file="$1" destination="$2"
  # Identical already: no write, so the FAT ESP is not rewritten every update.
  cmp -s "$source_file" "$destination" && return 0
  cp -f "$source_file" "$destination.new" 2>/dev/null \
    || { rm -f "$destination.new"; return 1; }
  mv -f "$destination.new" "$destination" \
    || { rm -f "$destination.new"; return 1; }
  cmp -s "$source_file" "$destination"
}

# Estimated bytes the planned files need on an ESP: the sum of their sizes plus
# the largest file again, since temp+rename transiently holds both the old and
# the new copy of the file being written (ADR 0038).
esp_kernel_sync_needed_bytes() {
  local esp_directory="$1" boot_directory="$2" file size total=0 max=0
  while IFS= read -r file; do
    size=$(stat -c%s "$boot_directory/$file" 2>/dev/null || echo 0)
    total=$((total + size))
    ((size > max)) && max=$size
  done < <(esp_kernel_sync_planned_files "$esp_directory" "$boot_directory")
  echo $((total + max))
}

# Bytes the planned files ALREADY occupy on the ESP. A re-sync overwrites these
# in place, so they are not fresh demand on free space — only the transient .new
# of the largest file is. On a populated ESP the prior copies are counted both
# as "used" (hence absent from free) and as "needed"; subtracting them here is
# what stops the preflight false-aborting a re-sync on a small ESP (ADR 0038).
esp_kernel_sync_present_bytes() {
  local esp_directory="$1" boot_directory="$2" file size total=0
  while IFS= read -r file; do
    size=$(stat -c%s "$esp_directory/$file" 2>/dev/null || echo 0)
    total=$((total + size))
  done < <(esp_kernel_sync_planned_files "$esp_directory" "$boot_directory")
  echo "$total"
}

# True when an ESP with <free_bytes> available can hold the planned files. One
# shared proxy for both the PreTransaction preflight and the PostTransaction
# guard. The prior copies of the planned files (present_bytes) are freed as they
# are overwritten, so they count toward the budget alongside free space.
esp_kernel_sync_space_ok() {
  local esp_directory="$1" boot_directory="$2" free="$3" needed present
  needed="$(esp_kernel_sync_needed_bytes "$esp_directory" "$boot_directory")"
  present="$(esp_kernel_sync_present_bytes "$esp_directory" "$boot_directory")"
  ((free + present >= needed))
}

# True when <dir> is a mount target listed in <mounts_file> (default the live
# /proc/self/mounts). If the ESP is NOT mounted, the sync would copy kernels
# into the ZFS /boot/efi DIRECTORY, leaving the real ESP stale and bricking the
# next boot — the preflight asserts this before any package is touched. Pure +
# testable: tests pass a fixture mounts file (ADR 0038).
esp_kernel_sync_is_mountpoint() {
  local directory mounts="${2:-/proc/self/mounts}" _device target _rest
  directory="$(esp_kernel_sync_without_slash "$1")"
  [[ -n "$directory" && -r "$mounts" ]] || return 1
  # Each mounts line is "<device> <target> <type> …".
  while read -r _device target _rest; do
    [[ "$target" == "$directory" ]] && return 0
  done < "$mounts"
  return 1
}

# True when <script> is a well-formed executable: it exists, is executable, and
# begins with a #! shebang. A pacman Exec= runs straight through execv with no
# shell, so a script with no shebang fails ENOEXEC ("Exec format error"); as a
# PostTransaction hook that silently leaves the ESP stale. The preflight
# self-checks this so a malformed sync script aborts the upgrade up front (via
# AbortOnFail) instead of bricking on the next boot (ADR 0038).
esp_kernel_sync_script_ok() {
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
esp_kernel_sync_prune_dead_fallback_entries() {
  local esp_directory entry referenced_file
  esp_directory="$(esp_kernel_sync_without_slash "$1")"
  for entry in "$esp_directory"/loader/entries/*.conf; do
    [[ -f "$entry" ]] || continue
    while IFS= read -r referenced_file; do
      if [[ "$referenced_file" == *fallback* \
            && ! -f "$esp_directory/$referenced_file" ]]; then
        rm -f "$entry"
        break
      fi
    done < <(esp_kernel_sync_entry_files "$entry" initrd)
  done
  return 0
}

# esp_kernel_sync_kernel_base <image> — the kernel package an ESP kernel
# image is named for: …/vmlinuz-linux-lts → linux-lts.
esp_kernel_sync_kernel_base() {
  # The file name after its 8-character "vmlinuz-" prefix.
  basename "$1" | cut -c9-
}

# esp_kernel_sync_kernels_current <esp_dir> <boot_dir> — 0 when every kernel
# staged on the ESP exists in /boot and matches it: the sync really put the
# installed kernels in place. False after an Interrupted Kernel Transaction
# (/boot lost its kernel), when the Module Stash must stay.
esp_kernel_sync_kernels_current() {
  local esp_directory="$1" boot_directory="$2" image base
  for image in "$esp_directory"/vmlinuz-*; do
    [[ -f "$image" ]] || continue
    base="$(esp_kernel_sync_kernel_base "$image")"
    [[ "$base" == *-prev ]] && continue
    cmp -s "$boot_directory/vmlinuz-$base" "$image" || return 1
  done
  return 0
}

# ── previous kernel pairs (ADR 0166) ─────────────────────────────────────────
# At the start of every transaction, each kernel's current kernel + default
# initramfs are kept as vmlinuz-<base>-prev / initramfs-<base>-prev.img, so the
# previous pair always matches the state the Update Snapshot captures: the pair
# Undo Last Update boots after rolling back to it. Refreshed only when it
# differs (once per kernel upgrade). Stable names, so loader entries never
# change. Optional: skipped when it won't fit.

# Pure: the package base of every kernel staged on <esp_dir> whose -prev pair
# is missing or differs from its current pair — kernel or initramfs (an
# initramfs-only rebuild, e.g. zfs-dkms or a HOOKS change, counts).
esp_kernel_sync_stale_previous() {
  local esp_directory="$1" image base
  for image in "$esp_directory"/vmlinuz-*; do
    [[ -f "$image" ]] || continue
    base="$(esp_kernel_sync_kernel_base "$image")"
    [[ "$base" == *-prev ]] && continue
    if ! cmp -s "$image" "$esp_directory/vmlinuz-$base-prev" \
       || ! cmp -s "$esp_directory/initramfs-$base.img" \
              "$esp_directory/initramfs-$base-prev.img"; then
      printf '%s\n' "$base"
    fi
  done
  return 0
}

# Bytes the current pair of <base> occupies on <esp_dir> — what keeping it as
# the previous pair costs.
esp_kernel_sync_pair_bytes() {
  local esp_directory="$1" base="$2" file total=0
  for file in "vmlinuz-$base" "initramfs-$base.img"; do
    [[ -f "$esp_directory/$file" ]] \
      && total=$((total + $(stat -c%s "$esp_directory/$file")))
  done
  echo "$total"
}

# Copy <base>'s current pair on <esp_dir> to its -prev names, each via a temp
# file then rename, so the current pair is never touched and a cut-off copy
# leaves only a sweepable .new.
esp_kernel_sync_keep_previous() {
  local esp_directory base="$2"
  esp_directory="$(esp_kernel_sync_without_slash "$1")"
  # Each image of the pair, kernel then initramfs, copied to its -prev
  # name: vmlinuz-<base> → vmlinuz-<base>-prev, initramfs-<base>.img →
  # initramfs-<base>-prev.img.
  if [[ -f "$esp_directory/vmlinuz-$base" ]]; then
    esp_kernel_sync_install_critical "$esp_directory/vmlinuz-$base" \
      "$esp_directory/vmlinuz-$base-prev" || return 1
  fi
  if [[ -f "$esp_directory/initramfs-$base.img" ]]; then
    esp_kernel_sync_install_critical "$esp_directory/initramfs-$base.img" \
      "$esp_directory/initramfs-$base-prev.img" || return 1
  fi
}

# True when <esp_dir>, with <free_bytes> available, still has room for <base>'s
# previous pair once the sync has written the new images.
esp_kernel_sync_previous_fits() {
  local esp_directory="$1" boot_directory="$2" free="$3" base="$4"
  local needed present
  needed="$(esp_kernel_sync_needed_bytes "$esp_directory" "$boot_directory")"
  present="$(esp_kernel_sync_present_bytes "$esp_directory" "$boot_directory")"
  ((free + present - needed >= $(esp_kernel_sync_pair_bytes \
    "$esp_directory" "$base")))
}

# esp_kernel_sync_drop_previous <esp_dir> <base> — Undo has no pair for <base>
# on that ESP from here on.
esp_kernel_sync_drop_previous() {
  local esp_directory
  esp_directory="$(esp_kernel_sync_without_slash "$1")"
  rm -f "$esp_directory/vmlinuz-$2-prev" \
    "$esp_directory/initramfs-$2-prev.img"
}

# Lib-only sourcing (tests, the installer, the retrofit): also load the
# install-time half, then skip the runtime below.
if [[ "${ESP_KERNEL_SYNC_LIB_ONLY:-0}" == "1" ]]; then
  # shellcheck source=esp-kernel-sync-install.sh
  source "$(dirname "${BASH_SOURCE[0]}")/esp-kernel-sync-install.sh"
  return 0
fi

# _esp_kernel_sync_free_bytes <esp_dir> — the ESP's free space in bytes (0
# when df cannot tell).
_esp_kernel_sync_free_bytes() {
  local free
  # The number under df's "Avail" header, digits only.
  free="$(df -B1 --output=avail "$1" 2>/dev/null | tail -n 1 | tr -dc '0-9')"
  printf '%s\n' "${free:-0}"
}

# Runtime: mirror /boot onto every mounted ESP, fail-closed on a critical copy.
# The primary ESP (/boot/efi) holds the loader entries that drive the plan.
_esp_kernel_sync_run() {
  _esp_kernel_sync_require_mounted
  _esp_kernel_sync_sweep_temporaries
  _esp_kernel_sync_copy_critical
  _esp_kernel_sync_copy_optional

  # Keep fallback boot entries consistent with the fallback image's presence, so
  # an entry never dead-ends on a missing initrd.
  local esp_directory
  for esp_directory in /boot/efi*/; do
    esp_directory="$(esp_kernel_sync_without_slash "$esp_directory")"
    esp_kernel_sync_prune_dead_fallback_entries "$esp_directory"
  done

  # The new kernel is on every ESP: the Module Stash has done its job
  # (ADR 0166). Critical-copy failures exited above, so this runs only on
  # success.
  if [[ -x /usr/local/lib/archzfs/boot-recovery.sh ]] \
     && esp_kernel_sync_kernels_current /boot/efi /boot; then
    /usr/local/lib/archzfs/boot-recovery.sh drop-stash || true
  fi

  # Explicit success: the pruning helper's trailing test must not become the
  # hook's exit status — a normal run with nothing to prune is not a failure.
  return 0
}

# Refuse to run if any ESP is not mounted: writing into the ZFS /boot/efi
# DIRECTORY would leave the real ESP stale and brick the next boot. The
# preflight already asserts this; this is defence-in-depth for a direct or
# un-preflighted invocation (ADR 0038).
_esp_kernel_sync_require_mounted() {
  local esp_directory
  for esp_directory in /boot/efi*/; do
    esp_directory="$(esp_kernel_sync_without_slash "$esp_directory")"
    esp_kernel_sync_is_mountpoint "$esp_directory" || {
      echo "esp-kernel-sync: FATAL: $esp_directory is not a mountpoint —" \
           "refusing to write boot images into the ZFS directory, not the" \
           "ESP." >&2
      exit 1
    }
  done
}

# Sweep orphaned temp files from a prior interrupted run.
_esp_kernel_sync_sweep_temporaries() {
  local esp_directory temporary_file
  for esp_directory in /boot/efi*/; do
    esp_directory="$(esp_kernel_sync_without_slash "$esp_directory")"
    while IFS= read -r temporary_file; do
      rm -f "$temporary_file"
    done < <(esp_kernel_sync_orphan_temporaries "$esp_directory")
  done
}
# Previous mode (PreTransaction, every transaction): refresh each stale previous
# pair on every ESP from the current pair, before pacman changes anything
# (ADR 0166). A stale pair always goes first; a pair that will not fit beside
# the room the sync needs is skipped with a warning. Never fails the
# transaction — an unmounted ESP is the kernel-transaction preflight's job.
# an unmounted ESP is the kernel-transaction preflight's job, not this one's.
_esp_kernel_sync_keep_previous_pairs() {
  local base esp_directory free
  for esp_directory in /boot/efi*/; do
    esp_directory="$(esp_kernel_sync_without_slash "$esp_directory")"
    esp_kernel_sync_is_mountpoint "$esp_directory" || continue
    # Per ESP: a secondary ESP is only mirrored on kernel transactions, so its
    # pairs can lag the primary's.
    while IFS= read -r base; do
      esp_kernel_sync_drop_previous "$esp_directory" "$base"
      free="$(_esp_kernel_sync_free_bytes "$esp_directory")"
      if esp_kernel_sync_previous_fits "$esp_directory" /boot \
           "$free" "$base" \
         && esp_kernel_sync_keep_previous "$esp_directory" "$base"; then
        continue
      fi
      esp_kernel_sync_drop_previous "$esp_directory" "$base"
      echo "esp-kernel-sync: WARN: no room for the previous $base on" \
           "$esp_directory — Undo Last Update unavailable for it." >&2
    done < <(esp_kernel_sync_stale_previous "$esp_directory")
  done
  # The Undo entry follows the Primary Kernel's previous pair (ADR 0166).
  if [[ -x /usr/local/lib/archzfs/undo-entry.sh ]]; then
    /usr/local/lib/archzfs/undo-entry.sh reconcile || true
  fi
  return 0
}

# Critical files MUST land intact on every ESP, or fail the transaction.
_esp_kernel_sync_copy_critical() {
  local file esp_directory
  while IFS= read -r file; do
    for esp_directory in /boot/efi*/; do
      esp_kernel_sync_install_critical "/boot/$file" \
        "$esp_directory/$file" || {
        echo "esp-kernel-sync: FATAL: could not write $file to" \
             "$esp_directory (ESP full?) — boot images left intact," \
             "failing the transaction." >&2
        df -h "$esp_directory" >&2
        exit 1
      }
    done
  done < <(esp_kernel_sync_critical_files /boot/efi /boot)
}

# Optional files (fallback) are best-effort: a failed copy is skipped and any
# truncated remnant removed, never failing the transaction.
_esp_kernel_sync_copy_optional() {
  local file esp_directory
  while IFS= read -r file; do
    for esp_directory in /boot/efi*/; do
      cmp -s "/boot/$file" "$esp_directory/$file" && continue
      cp -f "/boot/$file" "$esp_directory/$file" 2>/dev/null || {
        rm -f "$esp_directory/$file"
        echo "esp-kernel-sync: WARN: skipped optional $file on" \
             "$esp_directory (no room)." >&2
      }
    done
  done < <(esp_kernel_sync_optional_files /boot/efi /boot)
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
  local esp_directory free

  esp_kernel_sync_script_ok "$0" || {
    echo "esp-kernel-sync: PRE-TRANSACTION ABORT: sync script '$0' is not a" \
         "well-formed executable (missing #! shebang?). Fix it before" \
         "upgrading, or the ESP would be left stale (ADR 0038)." >&2
    exit 1
  }

  for esp_directory in /boot/efi*/; do
    esp_directory="$(esp_kernel_sync_without_slash "$esp_directory")"
    esp_kernel_sync_is_mountpoint "$esp_directory" || {
      echo "esp-kernel-sync: PRE-TRANSACTION ABORT: $esp_directory is not a" \
           "mountpoint —" \
           "the ESP is not mounted. Mount it before upgrading, or the new" \
           "kernel would not reach the ESP (ADR 0038)." >&2
      exit 1
    }
    free="$(_esp_kernel_sync_free_bytes "$esp_directory")"
    esp_kernel_sync_space_ok /boot/efi /boot "$free" || {
      echo "esp-kernel-sync: PRE-TRANSACTION ABORT: ESP $esp_directory lacks" \
           "room for the" \
           "new boot images. Free space and retry (ADR 0038)." >&2
      df -h "$esp_directory" >&2
      exit 1
    }
  done
}

case "${1:-sync}" in
preflight) _esp_kernel_sync_preflight ;;
previous)  _esp_kernel_sync_keep_previous_pairs ;;
*)         _esp_kernel_sync_run ;;
esac
