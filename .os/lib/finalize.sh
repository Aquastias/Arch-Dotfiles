#!/usr/bin/env bash
# =============================================================================
# lib/finalize.sh — Post-install cleanup and completion summary
# =============================================================================
# Sourced by 03-install.sh.
# Requires: lib/common.sh already sourced; LAYOUT_ESP_PARTS,
# LAYOUT_OS_POOL_NAME,
#           LAYOUT_DATA_POOL_NAME populated by the active layout module.
#
# Provides:
#   finalize  — unmounts ESPs and ZFS datasets, exports pools, prints summary
# =============================================================================

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

  # ── Unmount all ZFS datasets ──────────────────────────────────────────────
  # zfs umount -a unmounts everything mounted under MOUNT_ROOT's alt-root.
  zfs umount -a 2>/dev/null || true

  # ── Export pools ──────────────────────────────────────────────────────────
  # Exporting writes a clean "last_txg" and clears the active flag so the
  # pools are importable on the installed system without -f (force).
  local rp="${LAYOUT_OS_POOL_NAME}"
  local dp="${LAYOUT_DATA_POOL_NAME}"
  zpool export "${rp}" 2>/dev/null || warn "Could not export ${rp} cleanly."
  if [[ -n "$dp" ]]; then
    zpool export "${dp}" 2>/dev/null || true
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

  # ── Pool import recovery hint ─────────────────────────────────────────────
  # Shown in case zfs-import-cache doesn't find the pools on first boot
  # (e.g. if /etc/zfs/zpool.cache was missing or the hostid changed).
  warn "If ZFS pools fail to import on first boot, boot the live ISO and run:"
  echo "    zpool import -f ${rp}"
  if [[ -n "$dp" ]]; then
    echo "    zpool import -f ${dp}"
  fi

  echo ""
  echo -e "  ${DIM}ZFS encryption passphrase is required at every boot" \
          "(if encryption was enabled).${NC}"
  echo ""
}
