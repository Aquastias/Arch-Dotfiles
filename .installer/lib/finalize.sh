#!/usr/bin/env bash
# =============================================================================
# lib/finalize.sh — Post-install cleanup and completion summary
# =============================================================================
# Sourced by 03-install.sh.
# Requires: lib/common.sh already sourced; LAYOUT_ESP_PARTS,
# LAYOUT_OS_POOL_NAME,
#           LAYOUT_DATA_POOL_NAMES populated by the active layout module.
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

  # ── Unmount ESPs ──────────────────────────────────────────────────────────
  # Secondary ESPs must be unmounted before the primary, and all before
  # ZFS datasets, to avoid "target is busy" errors.
  local esp_count="${#LAYOUT_ESP_PARTS[@]}"
  local i
  for i in $(seq $((esp_count - 1)) -1 1); do
    umount "${MOUNT_ROOT}/boot/efi${i}" 2>/dev/null || true
  done
  ((esp_count >= 1)) && umount "${MOUNT_ROOT}/boot/efi" 2>/dev/null || true

  # ── Unmount the installed root ────────────────────────────────────────────
  if command_exists zpool; then
    # Drop NON-zfs data-group mounts under the install root first (ADR 0043) —
    # see _finalize_nonzfs_mounts.
    if command_exists findmnt; then
      local _mp
      while IFS= read -r _mp; do
        [[ -n "$_mp" ]] || continue
        umount "$_mp" 2>/dev/null || umount -l "$_mp" 2>/dev/null || true
      done < <(findmnt -rno TARGET,FSTYPE -R "${MOUNT_ROOT}" 2>/dev/null \
                | _finalize_nonzfs_mounts)
    fi

    # ZFS: unmount datasets (alt-root) then export pools — exporting writes a
    # clean last_txg and clears the active flag so they import without -f.
    zfs umount -a 2>/dev/null || true
    local rp="${LAYOUT_OS_POOL_NAME}"
    _finalize_export_pool "${rp}" || warn "Could not export ${rp} cleanly."
    local dp
    for dp in "${LAYOUT_DATA_POOL_NAMES[@]}"; do
      zpool export "${dp}" 2>/dev/null || true
    done
  else
    # Non-ZFS root (ext4/xfs/btrfs): recursively unmount everything under
    # MOUNT_ROOT before reboot (ADR 0043).
    umount -R "${MOUNT_ROOT}" 2>/dev/null || true
  fi

  # ── Completion message ────────────────────────────────────────────────────
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

  # ── Pool import recovery hint (ZFS only) ──────────────────────────────────
  # Shown in case zfs-import-cache doesn't find the pools on first boot
  # (e.g. if /etc/zfs/zpool.cache was missing or the hostid changed).
  if command_exists zpool; then
    warn "If ZFS pools fail to import on first boot, boot the live ISO and run:"
    echo "    zpool import -f ${LAYOUT_OS_POOL_NAME}"
    local dp2
    for dp2 in "${LAYOUT_DATA_POOL_NAMES[@]}"; do
      echo "    zpool import -f ${dp2}"
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
  local d r
  for d in "${FINALIZE_PROC:-/proc}"/[0-9]*; do
    r="$(readlink "$d/root" 2>/dev/null)" || continue
    [[ "$r" == "$MOUNT_ROOT" || "$r" == "$MOUNT_ROOT/"* ]] \
      && echo "${d##*/}"
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
  local p="${1:-}" pr="${FINALIZE_PROC:-/proc}" d l t ns self z
  local -A seen=()
  self="$(readlink "$pr/self/ns/mnt" 2>/dev/null)" || self=""
  for d in "$pr"/[0-9]*; do
    for l in "$d"/cwd "$d"/root "$d"/fd/*; do
      t="$(readlink "$l" 2>/dev/null)" || continue
      [[ "$t" == "$MOUNT_ROOT"/* || "$t" == /dev/zd* ]] || continue
      echo "${d##*/} $(cat "$d/comm" 2>/dev/null) $t"
    done
    [[ -n "$p" ]] || continue
    ns="$(readlink "$d/ns/mnt" 2>/dev/null)" || continue
    [[ "$ns" != "$self" && -z "${seen[$ns]:-}" ]] || continue
    seen[$ns]=1
    awk -v p="$p" -v pid="${d##*/}" -v c="$(cat "$d/comm" 2>/dev/null)" '
      { for (i = 1; i <= NF; i++) if ($i == "-") break
        s = $(i + 2) }
      $(i + 1) == "zfs" && (s == p || index(s, p "/") == 1 \
        || index(s, p "@") == 1) { print pid, c, "mount-ns", $5, s }
    ' "$d/mountinfo" 2>/dev/null
  done
  [[ -n "$p" ]] || return 0
  for z in "${FINALIZE_SYS:-/sys}"/block/zd*/holders/*; do
    [[ -e "$z" ]] || continue
    t="${z%/holders/*}"; echo "${t##*/} held by ${z##*/}"
  done
  return 0
}

# _finalize_export_pool <pool> — export, so the first boot imports without
# -f. A pool left imported (a live-ISO process still holding the target)
# fails the initramfs import (greetd/tuned, Audit Run 20261004): retry,
# then kill the target's users, retry, then force; log why on failure.
_finalize_export_pool() {
  local p="$1" i m src pid err
  for i in 1 2 3; do
    zpool export "$p" 2>/dev/null && return 0
    sleep 2; zfs umount -a 2>/dev/null || true
  done
  # kill only users of this pool's datasets still mounted — never `-m` a path
  # that is no longer a mountpoint (that is the live ISO's root: the
  # installer itself). `|| true`: no match is rc 1, and set -E carries the
  # installer's ERR trap into the substitution (refind/ufw 20261006)
  while read -r m src; do
    [[ "$src" == "$p" || "$src" == "$p/"* ]] || continue
    fuser -km "$m" >/dev/null 2>&1 || true
  done < <(findmnt -rn -t zfs -o TARGET,SOURCE 2>/dev/null || true)
  for pid in $(_finalize_chrooted_pids); do
    kill -KILL "$pid" 2>/dev/null || true
  done
  for i in 1 2 3; do
    sleep 2; zfs umount -a 2>/dev/null || true
    zpool export "$p" 2>/dev/null && return 0
  done
  err="$(zpool export -f "$p" 2>&1)" && return 0
  warn "zpool export ${p}: ${err:-failed}"
  _finalize_holders "$p" | while IFS= read -r h; do warn "holder: $h"; done
  return 1
}
