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

# Given `findmnt -rno TARGET,FSTYPE` lines on stdin, print the NON-zfs mount
# targets deepest-path-first. finalize unmounts these (data-group disks:
# ext4/xfs/btrfs, possibly via a LUKS mapper) BEFORE exporting the zfs pools: a
# stale non-zfs mount under ${MOUNT_ROOT} holds it busy, so `zpool export` fails
# and the pool stays active → the initramfs import panics next boot ("pool was
# previously in use from another system", ADR 0043). Pure: a string transform.
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
  if command -v zpool >/dev/null 2>&1; then
    # Drop any NON-zfs data-group mounts under the install root first (ext4/xfs/
    # btrfs, ADR 0043) — they hold ${MOUNT_ROOT} busy, which would fail the
    # export below and leave the pool active (initramfs panic next boot).
    if command -v findmnt >/dev/null 2>&1; then
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
    zpool export "${rp}" 2>/dev/null || warn "Could not export ${rp} cleanly."
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
  if command -v zpool >/dev/null 2>&1; then
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
