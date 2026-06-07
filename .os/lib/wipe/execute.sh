#!/usr/bin/env bash
# =============================================================================
# lib/wipe/execute.sh — the Disk Wipe Executor (device-aware, I/O)
# =============================================================================
# Owns the destructive, device-aware wipe: per-disk ZFS/LVM/MD teardown, the
# make-blank pass (blkdiscard on SSD/NVMe via the Wipe-Method Selector, a dd
# zero-pass on HDD), and the parallel per-disk progress orchestration. 02-wipe.sh
# is the thin orchestrator that resolves the target set and calls run_parallel_wipe.
#
# This is block-device I/O, not unit-tested — the real wipe path is covered by
# the VM smoke tests. The decidable parts (method routing, prior-state, progress
# maths) live in their own pure modules (method.sh, prior-state.sh, progress.sh).
#
# Sourced by 02-wipe.sh. main()-free, so sourcing is inert. Colour codes and the
# info/warn/section helpers come from common.sh, which the orchestrator sources.
# =============================================================================

# shellcheck source=method.sh
[[ "$(type -t wipe_method)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/method.sh"
# shellcheck source=progress.sh
[[ "$(type -t progress_line)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/progress.sh"

# =============================================================================
# PRE-WIPE TEARDOWN (ZFS / LVM / MD-RAID)
# =============================================================================

teardown_zfs() {
  local disk="$1"
  command -v zpool &>/dev/null || return 0

  # Destroy any already-imported pools using this disk.
  # Pool names cannot contain whitespace, so word-splitting is safe.
  local pool
  while IFS= read -r pool; do
    [[ -z "$pool" ]] && continue
    if zpool status "$pool" 2>/dev/null | grep -q "$(basename "$disk")"; then
      warn "Destroying imported ZFS pool '${pool}' on ${disk}"
      zpool destroy -f "$pool" 2>/dev/null || true
    fi
  done < <(zpool list -H -o name 2>/dev/null || true)

  # Try to import and then destroy any un-imported pools on this disk.
  # Limit the device scan to /dev to avoid hanging on network devices.
  local pools
  pools="$(zpool import -d /dev 2>/dev/null | awk '/pool:/{print $2}' || true)"
  for pool in $pools; do
    zpool import -N -d /dev "$pool" 2>/dev/null || continue
    if zpool status "$pool" 2>/dev/null | grep -q "$(basename "$disk")"; then
      warn "Destroying ZFS pool '${pool}' on ${disk}"
      zpool destroy -f "$pool" 2>/dev/null || true
    else
      zpool export "$pool" 2>/dev/null || true
    fi
  done
}

teardown_lvm() {
  local disk="$1"
  command -v pvs &>/dev/null || return 0
  while IFS= read -r pv; do
    local vg
    vg="$(pvs --noheadings -o vg_name "$pv" 2>/dev/null | xargs || true)"
    if [[ -n "$vg" ]]; then
      warn "Removing LVM VG '${vg}' on ${pv}"
      vgremove -f "$vg" 2>/dev/null || true
    fi
    pvremove -f "$pv" 2>/dev/null || true
  done < <(pvs --noheadings -o pv_name 2>/dev/null \
    | grep "^[[:space:]]*${disk}" || true)
}

teardown_mdraid() {
  local disk="$1"
  command -v mdadm &>/dev/null || return 0
  while IFS= read -r part; do
    local md
    md="$(mdadm --query "/dev/${part}" 2>/dev/null |
      awk '/is a member of/{print $NF}' || true)"
    if [[ -n "$md" && -b "$md" ]]; then
      warn "Stopping MD array ${md} (contains /dev/${part})"
      mdadm --stop "$md" 2>/dev/null || true
    fi
  done < <(lsblk -ln -o NAME "$disk" 2>/dev/null | tail -n +2)
}

# =============================================================================
# SINGLE DISK WIPE (runs in background per disk)
# =============================================================================

wipe_one_disk() {
  local disk="$1"
  local log prog base
  base="$(basename "$disk")"
  log="/tmp/wipe-${base}.log"
  prog="/tmp/wipe-${base}.progress"
  {
    echo "[$(date '+%T')] Starting: $disk"

    teardown_zfs "$disk"
    teardown_lvm "$disk"
    teardown_mdraid "$disk"

    # Clear all filesystem/partition signatures
    wipefs -af "$disk"

    # Destroy GPT and MBR partition tables
    sgdisk --zap-all "$disk"

    # Device-aware clear (Wipe-Method Selector): blkdiscard for SSD/NVMe,
    # a single dd zero-pass for HDD. dd exits non-zero at end-of-disk ("no
    # space left"), which is expected — `|| true` suppresses it.
    local rota method
    rota="$(lsblk -dno ROTA "$disk" 2>/dev/null | head -n1 | xargs || true)"
    method="$(wipe_method "$rota")"
    if [[ "$method" == "blkdiscard" ]]; then
      echo "[$(date '+%T')] Discarding $disk (SSD/NVMe)..."
      if ! blkdiscard -f "$disk" 2>/dev/null; then
        # USB bridges / drives that reject discard: fall back to a zero-pass
        # so the disk still ends up blank.
        echo "[$(date '+%T')] blkdiscard unsupported — zero-filling $disk..."
        dd if=/dev/zero of="$disk" bs=4M conv=fsync status=progress \
          2>"$prog" || true
      fi
    else
      echo "[$(date '+%T')] Zero-filling $disk (this takes a while)..."
      dd if=/dev/zero of="$disk" bs=4M conv=fsync status=progress \
        2>"$prog" || true
    fi

    # Second wipefs pass — catches any leftover signatures at end-of-disk
    wipefs -af "$disk" 2>/dev/null || true

    # Ask kernel to re-read the (now empty) partition table
    blockdev --rereadpt "$disk" 2>/dev/null || true

    echo "[$(date '+%T')] Done: $disk"
  } >"$log" 2>&1
}

# =============================================================================
# PARALLEL WIPE ORCHESTRATION
# =============================================================================

run_parallel_wipe() {
  section "Wiping Disks (parallel)"

  declare -a pids disk_map size_map method_map
  local disk
  for disk in "${DISKS_TO_WIPE[@]}"; do
    # Capture size + method up front so the live display can draw a bar (HDD)
    # or show instant completion (blkdiscard) without re-querying each tick.
    local rota
    rota="$(lsblk -dno ROTA "$disk" 2>/dev/null | head -n1 | xargs || true)"
    size_map+=("$(blockdev --getsize64 "$disk" 2>/dev/null || echo 0)")
    method_map+=("$(wipe_method "$rota")")
    rm -f "/tmp/wipe-$(basename "$disk").progress"
    info "Spawning wipe job: $disk"
    wipe_one_disk "$disk" &
    pids+=($!)
    disk_map+=("$disk")
  done

  echo ""
  info "${#DISKS_TO_WIPE[@]} disk(s) wiping in parallel."
  info "Logs: /tmp/wipe-<diskname>.log"
  echo ""

  # Live per-disk display — a stable multi-line block redrawn ~1 s in place.
  # HDD dd jobs show a real bar (bytes from their .progress file against the
  # disk size); blkdiscard jobs show near-instant completion. ANSI cursor-up
  # anchors the block. Non-tty output (logs/CI) still works — the escapes are
  # harmless and the lines simply scroll.
  local n=${#pids[@]} start=$SECONDS first=1 all_done=false
  while ! $all_done; do
    all_done=true
    local elapsed=$((SECONDS - start))
    local lines=() i
    for i in "${!pids[@]}"; do
      local disk_i base size method bytes
      disk_i="${disk_map[$i]}"; base="$(basename "$disk_i")"
      size="${size_map[$i]}"; method="${method_map[$i]}"
      if kill -0 "${pids[$i]}" 2>/dev/null; then
        all_done=false
        bytes="$(progress_parse_bytes \
          "$(cat "/tmp/wipe-${base}.progress" 2>/dev/null || true)")"
        if [[ -n "$bytes" ]]; then
          lines+=("  ${YELLOW}●${NC} $(progress_line "$base" "$bytes" \
            "$size" "$elapsed")")
        elif [[ "$method" == "blkdiscard" ]]; then
          lines+=("  ${YELLOW}●${NC} ${base} discarding (SSD/NVMe)…")
        else
          lines+=("  ${YELLOW}●${NC} ${base} starting…")
        fi
      elif grep -q "Done:" "/tmp/wipe-${base}.log" 2>/dev/null; then
        lines+=("  ${GREEN}✔${NC} ${base} $(progress_bar "$size" "$size" 20)\
 done")
      else
        lines+=("  ${YELLOW}!${NC} ${base} check log")
      fi
    done
    # Redraw the block in place: after the first paint, jump the cursor back up
    # over the N lines, clearing and reprinting each.
    if ((first)); then first=0; else printf '\033[%dA' "$n"; fi
    for i in "${lines[@]}"; do printf '\033[2K%b\n' "$i"; done
    $all_done || sleep 1
  done

  # Reap the finished jobs (the display loop detected completion via kill -0,
  # not wait). Status is ignored — the authoritative success signal is the
  # "Done:" line in each disk's log, collected below.
  for i in "${!pids[@]}"; do wait "${pids[$i]}" 2>/dev/null || true; done

  # Collect results from the "Done:" line written at the end of each disk's log.
  local any_failed=false
  local i
  for i in "${!pids[@]}"; do
    local log
    log="/tmp/wipe-$(basename "${disk_map[$i]}").log"
    if ! grep -q "Done:" "$log" 2>/dev/null; then
      warn "Wipe may have failed for ${disk_map[$i]} — check $log"
      any_failed=true
    fi
  done

  # NOTE: must not let this be the function's final command as a bare
  # `$any_failed && warn ...`; under `set -e` that returns 1 when any_failed is
  # false (the normal success case) and trips the ERR trap at the call site.
  if $any_failed; then
    warn "One or more wipes may need attention. Check logs above."
  fi
  return 0
}
