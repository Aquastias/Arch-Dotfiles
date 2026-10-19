#!/usr/bin/env bash
# =============================================================================
# lib/wipe/execute.sh — the Disk Wipe Executor (device-aware, I/O)
# =============================================================================
# Owns the destructive, device-aware wipe: per-disk ZFS/LVM/MD teardown, the
# make-blank pass (blkdiscard on SSD/NVMe via the Wipe-Method Selector, a dd
# zero-pass on HDD), and the parallel per-disk progress orchestration.
# 02-wipe.sh is the thin orchestrator that resolves the target set and calls
# wipe_run_parallel.
#
# The wipe itself is block-device I/O covered by the VM smoke tests; which pools
# and PVs the teardown claims is unit-tested (tests/wipe-teardown.bats). The
# other decidable parts (method routing, prior-state, progress maths) live in
# their own pure modules (method.sh, prior-state.sh, progress.sh).
#
# Sourced by 02-wipe.sh. main()-free, so sourcing is inert. Colour codes and the
# info/warn/section helpers come from common.sh, which the orchestrator sources.
# =============================================================================

# shellcheck source=method.sh
declare -F wipe_method >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/method.sh"
# shellcheck source=progress.sh
declare -F wipe_progress_line >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/progress.sh"

# =============================================================================
# PRE-WIPE TEARDOWN (ZFS / LVM / MD-RAID)
# =============================================================================

# _execute_device_on_disk <device> <disk> — 0 when <device> is <disk> itself or
# one of its partitions. Decided by device identity (resolved path, else the
# partition's parent disk), so a /dev/disk/by-id target matches the kernel
# nodes zpool and pvs report, and sda never matches sdab.
_execute_device_on_disk() {
  local device disk parent
  device="$(readlink -f "$1" 2>/dev/null)"; device="${device:-$1}"
  disk="$(readlink -f "$2" 2>/dev/null)"; disk="${disk:-$2}"
  [[ "$device" == "$disk" ]] && return 0
  parent="$(lsblk -no PKNAME "$device" 2>/dev/null | awk 'NR == 1')"
  [[ -n "$parent" && "/dev/${parent}" == "$disk" ]]
}

# _execute_pool_on_disk <pool> <disk> — 0 when any vdev of the imported <pool>
# lives on <disk>. `status -P -L` prints full, symlink-resolved vdev paths.
_execute_pool_on_disk() {
  local pool="$1" disk="$2" vdev
  while IFS= read -r vdev; do
    _execute_device_on_disk "$vdev" "$disk" && return 0
  done < <(zpool status -P -L "$pool" 2>/dev/null \
    | awk '$1 ~ "^/dev/" { print $1 }')
  return 1
}

wipe_teardown_zfs() {
  local disk="$1"
  command_exists zpool || return 0

  # Destroy any already-imported pools using this disk.
  # Pool names cannot contain whitespace, so word-splitting is safe.
  local pool
  while IFS= read -r pool; do
    [[ -z "$pool" ]] && continue
    if _execute_pool_on_disk "$pool" "$disk"; then
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
    if _execute_pool_on_disk "$pool" "$disk"; then
      warn "Destroying ZFS pool '${pool}' on ${disk}"
      zpool destroy -f "$pool" 2>/dev/null || true
    else
      zpool export "$pool" 2>/dev/null || true
    fi
  done
}

wipe_teardown_lvm() {
  local disk="$1" physical_volume volume_group
  command_exists pvs || return 0
  while IFS= read -r physical_volume; do
    [[ -n "$physical_volume" ]] || continue
    _execute_device_on_disk "$physical_volume" "$disk" || continue
    volume_group="$(pvs --noheadings -o vg_name "$physical_volume" 2>/dev/null \
      | awk '{ $1 = $1; print }' || true)"
    if [[ -n "$volume_group" ]]; then
      warn "Removing LVM VG '${volume_group}' on ${physical_volume}"
      vgremove -f "$volume_group" 2>/dev/null || true
    fi
    pvremove -f "$physical_volume" 2>/dev/null || true
  done < <(pvs --noheadings -o pv_name 2>/dev/null \
    | awk '{ $1 = $1; print }' || true)
}

wipe_teardown_mdraid() {
  local disk="$1" part array_device
  command_exists mdadm || return 0
  while IFS= read -r part; do
    array_device="$(mdadm --query "/dev/${part}" 2>/dev/null |
      awk '/is a member of/{print $NF}' || true)"
    if [[ -n "$array_device" && -b "$array_device" ]]; then
      warn "Stopping MD array ${array_device} (contains /dev/${part})"
      mdadm --stop "$array_device" 2>/dev/null || true
    fi
  done < <(lsblk -ln -o NAME "$disk" 2>/dev/null | awk 'NR > 1')
}

# _execute_rotational <disk> — lsblk's ROTA flag (1 HDD, 0 SSD/NVMe), trimmed;
# empty when lsblk cannot tell.
_execute_rotational() {
  lsblk -dno ROTA "$1" 2>/dev/null | awk 'NR == 1 { $1 = $1; print }' || true
}

# =============================================================================
# SINGLE DISK WIPE (runs in background per disk)
# =============================================================================

wipe_one_disk() {
  local disk="$1"
  local log progress_file disk_name
  disk_name="$(base_name "$disk")"
  log="/tmp/wipe-${disk_name}.log"
  progress_file="/tmp/wipe-${disk_name}.progress"
  {
    echo "[$(date '+%T')] Starting: $disk"

    wipe_teardown_zfs "$disk"
    wipe_teardown_lvm "$disk"
    wipe_teardown_mdraid "$disk"

    # Clear all filesystem/partition signatures
    wipefs -af "$disk"

    # Destroy GPT and MBR partition tables
    sgdisk --zap-all "$disk"

    # Device-aware clear (Wipe-Method Selector): blkdiscard for SSD/NVMe,
    # a single dd zero-pass for HDD. dd exits non-zero at end-of-disk ("no
    # space left"), which is expected — `|| true` suppresses it.
    local method
    method="$(wipe_method "$(_execute_rotational "$disk")")"
    if [[ "$method" == "blkdiscard" ]]; then
      echo "[$(date '+%T')] Discarding $disk (SSD/NVMe)..."
      if ! blkdiscard -f "$disk" 2>/dev/null; then
        # USB bridges / drives that reject discard: fall back to a zero-pass
        # so the disk still ends up blank.
        echo "[$(date '+%T')] blkdiscard unsupported — zero-filling $disk..."
        dd if=/dev/zero of="$disk" bs=4M conv=fsync status=progress \
          2>"$progress_file" || true
      fi
    else
      echo "[$(date '+%T')] Zero-filling $disk (this takes a while)..."
      dd if=/dev/zero of="$disk" bs=4M conv=fsync status=progress \
        2>"$progress_file" || true
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

wipe_run_parallel() {
  section "Wiping Disks (parallel)"

  # Dynamic scope: the _execute_* helpers below fill and read these per-job
  # arrays (index i is one disk's job).
  declare -a pids disk_map size_map method_map
  _execute_spawn_jobs

  echo ""
  info "${#DISKS_TO_WIPE[@]} disk(s) wiping in parallel."
  info "Logs: /tmp/wipe-<diskname>.log"
  echo ""

  _execute_live_display

  # Reap the finished jobs (the display loop detected completion via kill -0,
  # not wait). Status is ignored — the authoritative success signal is the
  # "Done:" line in each disk's log, collected below.
  local i
  for i in "${!pids[@]}"; do wait "${pids[$i]}" 2>/dev/null || true; done

  _execute_report_failures
  return 0
}

# _execute_spawn_jobs — start one background wipe_one_disk per
# DISKS_TO_WIPE entry, recording the caller's pids/disk_map/size_map/
# method_map. Size + method are captured up front so the live display can
# draw a bar (HDD) or show instant completion (blkdiscard) without
# re-querying each tick.
_execute_spawn_jobs() {
  local disk
  for disk in "${DISKS_TO_WIPE[@]}"; do
    size_map+=("$(blockdev --getsize64 "$disk" 2>/dev/null || echo 0)")
    method_map+=("$(wipe_method "$(_execute_rotational "$disk")")")
    rm -f "/tmp/wipe-$(base_name "$disk").progress"
    info "Spawning wipe job: $disk"
    wipe_one_disk "$disk" &
    pids+=($!)
    disk_map+=("$disk")
  done
}

# _execute_live_display — the live per-disk display: a stable multi-line block
# redrawn ~1 s in place until every job has exited. HDD dd jobs show a real
# bar (bytes from their .progress file against the disk size); blkdiscard
# jobs show near-instant completion. ANSI cursor-up anchors the block.
# Non-tty output (logs/CI) still works — the escapes are harmless and the
# lines simply scroll.
_execute_live_display() {
  local job_count=${#pids[@]} start=$SECONDS first=1 all_done=false
  local elapsed i line
  local -a lines
  while ! $all_done; do
    all_done=true
    elapsed=$((SECONDS - start))
    lines=()
    for i in "${!pids[@]}"; do
      if kill -0 "${pids[$i]}" 2>/dev/null; then
        all_done=false
        lines+=("$(_execute_running_line "$i" "$elapsed")")
      else
        lines+=("$(_execute_finished_line "$i")")
      fi
    done
    # Redraw the block in place: after the first paint, jump the cursor back
    # up over the N lines, clearing and reprinting each.
    if ((first)); then first=0; else printf '\033[%dA' "$job_count"; fi
    for line in "${lines[@]}"; do printf '\033[2K%b\n' "$line"; done
    $all_done || sleep 1
  done
  return 0
}

# _execute_running_line <index> <elapsed> — an in-flight job's status line.
_execute_running_line() {
  local disk_name size method bytes
  disk_name="$(base_name "${disk_map[$1]}")"
  size="${size_map[$1]}"; method="${method_map[$1]}"
  bytes="$(wipe_progress_parse_bytes \
    "$(cat "/tmp/wipe-${disk_name}.progress" 2>/dev/null || true)")"
  if [[ -n "$bytes" ]]; then
    printf '%s\n' "  ${YELLOW}●${NC} $(wipe_progress_line "$disk_name" \
      "$bytes" "$size" "$2")"
  elif [[ "$method" == "blkdiscard" ]]; then
    printf '%s\n' "  ${YELLOW}●${NC} ${disk_name} discarding (SSD/NVMe)…"
  else
    printf '%s\n' "  ${YELLOW}●${NC} ${disk_name} starting…"
  fi
}

# _execute_finished_line <index> — an exited job's status line: done when its
# log carries the "Done:" line, else a pointer to the log.
_execute_finished_line() {
  local disk_name size
  disk_name="$(base_name "${disk_map[$1]}")"
  size="${size_map[$1]}"
  if grep -q "Done:" "/tmp/wipe-${disk_name}.log" 2>/dev/null; then
    printf '%s\n' "  ${GREEN}✔${NC} ${disk_name} $(wipe_progress_bar "$size" \
      "$size" 20) done"
  else
    printf '%s\n' "  ${YELLOW}!${NC} ${disk_name} check log"
  fi
}

# _execute_report_failures — warn for every job whose log lacks the "Done:"
# line written at the end of a successful wipe.
_execute_report_failures() {
  local any_failed=false i log
  for i in "${!pids[@]}"; do
    log="/tmp/wipe-$(base_name "${disk_map[$i]}").log"
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
