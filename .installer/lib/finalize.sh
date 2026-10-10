#!/usr/bin/env bash
# =============================================================================
# lib/finalize.sh — Post-install cleanup and completion summary
# =============================================================================
# Used by: 03-install.sh.
# Requires: lib/common.sh already sourced; LAYOUT_ESP_PARTS,
# LAYOUT_OS_POOL_NAME, LAYOUT_DATA_POOL_NAMES populated by the active layout
# module.
#
# Provides:
#   finalize  — unmounts ESPs and ZFS datasets, exports pools, prints summary
# =============================================================================

# Given `findmnt -rno TARGET,FSTYPE` on stdin, print the NON-zfs mount targets
# deepest-first. finalize unmounts these before exporting the zfs pools: a stale
# non-zfs mount under ${MOUNT_ROOT} holds it busy, failing `zpool export` and
# leaving the pool active → initramfs import panic next boot (ADR 0043).
_finalize_nonzfs_mounts() {
  awk '$2 != "zfs" && $1 != "" { print length($1), $1 }' \
    | sort -rn | awk '{ print $2 }'
}

finalize() {
  section "Finalizing"
  _finalize_unmount_esps
  _finalize_unmount_root
  _finalize_print_completion
}

# Secondary ESPs must be unmounted before the primary, and all before
# ZFS datasets, to avoid "target is busy" errors.
_finalize_unmount_esps() {
  local esp_count="${#LAYOUT_ESP_PARTS[@]}"
  local i
  for ((i = esp_count - 1; i >= 1; i--)); do
    umount "${MOUNT_ROOT}/boot/efi${i}" 2>/dev/null || true
  done
  ((esp_count >= 1)) && umount "${MOUNT_ROOT}/boot/efi" 2>/dev/null || true
}

_finalize_unmount_root() {
  if ! command_exists zpool; then
    # Non-ZFS root (ext4/xfs/btrfs): recursively unmount everything under
    # MOUNT_ROOT before reboot (ADR 0043).
    umount -R "${MOUNT_ROOT}" 2>/dev/null || true
    return 0
  fi

  # Drop NON-zfs data-group mounts under the install root first (ADR 0043) —
  # see _finalize_nonzfs_mounts.
  if command_exists findmnt; then
    local mountpoint
    while IFS= read -r mountpoint; do
      [[ -n "$mountpoint" ]] || continue
      umount "$mountpoint" 2>/dev/null \
        || umount -l "$mountpoint" 2>/dev/null || true
    done < <(findmnt -rno TARGET,FSTYPE -R "${MOUNT_ROOT}" 2>/dev/null \
              | _finalize_nonzfs_mounts)
  fi

  # ZFS: unmount datasets (alt-root) then export pools — exporting writes a
  # clean last_txg and clears the active flag so they import without -f.
  zfs umount -a 2>/dev/null || true
  local os_pool="${LAYOUT_OS_POOL_NAME}"
  _finalize_export_pool "${os_pool}" \
    || warn "Could not export ${os_pool} cleanly."
  local data_pool
  for data_pool in "${LAYOUT_DATA_POOL_NAMES[@]}"; do
    zpool export "${data_pool}" 2>/dev/null || true
  done
}

_finalize_print_completion() {
  echo ""
  info "════════════════════════════════════════════════════"
  info " Installation complete.  Remove install media and reboot."
  info "════════════════════════════════════════════════════"
  echo ""
  echo -e "  ${BOLD}Steps completed:${NC}"
  echo -e "  ${GREEN}✔${NC}  01-bootstrap-zfs.sh"
  echo -e "  ${GREEN}✔${NC}  02-wipe.sh"
  echo -e "  ${GREEN}✔${NC}  03-install.sh"
  echo ""

  # Pool import recovery hint (ZFS only) — in case zfs-import-cache doesn't
  # find the pools on first boot (e.g. if /etc/zfs/zpool.cache was missing or
  # the hostid changed).
  if command_exists zpool; then
    warn "If ZFS pools fail to import on first boot, boot the live ISO and run:"
    echo "    zpool import -f ${LAYOUT_OS_POOL_NAME}"
    local data_pool
    for data_pool in "${LAYOUT_DATA_POOL_NAMES[@]}"; do
      echo "    zpool import -f ${data_pool}"
    done
  fi

  echo ""
  echo -e "  ${DIM}ZFS encryption passphrase is required at every boot" \
          "(if encryption was enabled).${NC}"
  echo ""
}

# _finalize_chrooted_pids — pids whose root is the install target: arch-chroot
# leftovers (gpg-agent…) that hold the pool with no mount for fuser to see.
_finalize_chrooted_pids() {
  local process_path process_root
  for process_path in "${FINALIZE_PROC:-/proc}"/[0-9]*; do
    process_root="$(readlink "$process_path/root" 2>/dev/null)" || continue
    [[ "$process_root" == "$MOUNT_ROOT" \
      || "$process_root" == "$MOUNT_ROOT/"* ]] \
      && echo "${process_path##*/}"
  done
  return 0
}

# _finalize_holders — "<pid> <comm> <path>" for each open file, cwd or root
# under the install target or on a zvol: what keeps a pool busy (laptop
# 20261008 stayed busy after the chroot kill, and the log never said why).
# With <pool>, also the kernel-side holders no file points at (efistub/ufw
# 20261008): the pool's mounts alive in another mount namespace (once per
# namespace) and zvols held by a kernel device.
_finalize_holders() {
  local pool="${1:-}" proc_root="${FINALIZE_PROC:-/proc}"
  local own_namespace process_path namespace
  local -A seen_namespaces=()
  own_namespace="$(readlink "$proc_root/self/ns/mnt" 2>/dev/null)" \
    || own_namespace=""
  for process_path in "$proc_root"/[0-9]*; do
    _finalize_open_files_on_target "$process_path"
    [[ -n "$pool" ]] || continue
    namespace="$(readlink "$process_path/ns/mnt" 2>/dev/null)" || continue
    [[ "$namespace" != "$own_namespace" \
      && -z "${seen_namespaces[$namespace]:-}" ]] || continue
    seen_namespaces[$namespace]=1
    _finalize_namespace_pool_mounts "$process_path" "$pool"
  done
  [[ -n "$pool" ]] || return 0
  _finalize_zvol_holders
}

# _finalize_open_files_on_target <process dir> — the process's cwd, root and
# open files that sit under the install target or on a zvol.
_finalize_open_files_on_target() {
  local process_path="$1" link target
  for link in "$process_path"/cwd "$process_path"/root "$process_path"/fd/*; do
    target="$(readlink "$link" 2>/dev/null)" || continue
    [[ "$target" == "$MOUNT_ROOT"/* || "$target" == /dev/zd* ]] || continue
    echo "${process_path##*/} $(cat "$process_path/comm" 2>/dev/null) $target"
  done
}

# _finalize_namespace_pool_mounts <process dir> <pool> — the pool's datasets
# mounted in the process's mount namespace.
_finalize_namespace_pool_mounts() {
  local process_path="$1" pool="$2"
  awk -v pool="$pool" -v pid="${process_path##*/}" \
      -v command="$(cat "$process_path/comm" 2>/dev/null)" '
    { for (field = 1; field <= NF; field++) if ($field == "-") break
      source = $(field + 2) }
    $(field + 1) == "zfs" && (source == pool || index(source, pool "/") == 1 \
      || index(source, pool "@") == 1) {
      print pid, command, "mount-ns", $5, source
    }
  ' "$process_path/mountinfo" 2>/dev/null
  return 0
}

# _finalize_zvol_holders — "<zvol> held by <device>" for each held zvol.
_finalize_zvol_holders() {
  local holder zvol
  for holder in "${FINALIZE_SYS:-/sys}"/block/zd*/holders/*; do
    [[ -e "$holder" ]] || continue
    zvol="${holder%/holders/*}"
    echo "${zvol##*/} held by ${holder##*/}"
  done
  return 0
}

# _finalize_export_pool <pool> — export, so the first boot imports without
# -f. A pool left imported (a live-ISO process still holding the target)
# fails the initramfs import (greetd/tuned, Audit Run 20261004): retry,
# then kill the target's users, retry, then force; log why on failure.
_finalize_export_pool() {
  local pool="$1" i mountpoint source pid error_output holder
  for i in 1 2 3; do
    zpool export "$pool" 2>/dev/null && return 0
    sleep 2; zfs umount -a 2>/dev/null || true
  done
  # kill only users of this pool's datasets still mounted — never `-m` a path
  # that is no longer a mountpoint (that is the live ISO's root: the
  # installer itself). `|| true`: no match is rc 1, and set -E carries the
  # installer's ERR trap into the substitution (refind/ufw 20261006)
  while read -r mountpoint source; do
    [[ "$source" == "$pool" || "$source" == "$pool/"* ]] || continue
    fuser -km "$mountpoint" >/dev/null 2>&1 || true
  done < <(findmnt -rn -t zfs -o TARGET,SOURCE 2>/dev/null || true)
  for pid in $(_finalize_chrooted_pids); do
    kill -KILL "$pid" 2>/dev/null || true
  done
  for i in 1 2 3; do
    sleep 2; zfs umount -a 2>/dev/null || true
    zpool export "$pool" 2>/dev/null && return 0
  done
  error_output="$(zpool export -f "$pool" 2>&1)" && return 0
  warn "zpool export ${pool}: ${error_output:-failed}"
  _finalize_holders "$pool" \
    | while IFS= read -r holder; do warn "holder: $holder"; done
  return 1
}
