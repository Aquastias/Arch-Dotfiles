#!/usr/bin/env bash
# =============================================================================
# 02-wipe.sh
# =============================================================================
# PURPOSE:
#   Completely wipes all detected physical disks so they appear brand new —
#   no partition tables, no filesystem signatures, no ZFS labels, no LVM
#   metadata, no RAID superblocks. After this script every disk is a blank
#   slate ready for the installer to partition from scratch.
#
# WHAT IT DOES PER DISK (in order):
#   1. Tears down any ZFS pools using that disk (import → destroy)
#   2. Deactivates any LVM physical volumes / volume groups on that disk
#   3. Stops any MD-RAID arrays that include partitions on that disk
#   4. wipefs -af           — clears all filesystem/partition signatures
#   5. sgdisk --zap-all     — destroys GPT + MBR partition tables
#   6. dd if=/dev/zero ...  — full zero-fill of the entire disk (every sector)
#   7. Second wipefs pass   — catches anything dd may have re-written
#   8. blockdev --rereadpt  — tells the kernel to re-read the empty table
#
# DISK DETECTION:
#   Auto-detects all block devices of type "disk" via lsblk.
#   Automatically SKIPS:
#     - The live USB/CD the system booted from
#     - Any disk with currently mounted partitions
#     - Loop devices, optical drives, RAM disks
#
# WIPE DEPTH:
#   Full zero-fill (dd). All disks are wiped IN PARALLEL to minimise total
#   wall-clock time. Progress is logged to /tmp/wipe-<diskname>.log.
#   Expect: SSDs/NVMe = minutes, HDDs = hours (at ~130 MB/s, 1TB ≈ 2h).
#
# RUN ORDER:
#   1. 01-bootstrap-zfs.sh
#   2. 02-wipe.sh            ← you are here
#   3. 03-install.sh
#
# USAGE:
#   chmod +x 02-wipe.sh
#   ./02-wipe.sh                    # interactive
#   ./02-wipe.sh -y     # unattended (no exclusions, skip WIPE prompt)
#   ./02-wipe.sh --unattended
#
# Honors INSTALL_UNATTENDED=1 from the environment as well as the CLI flag, so
# it works whether invoked directly or via install.sh.
# =============================================================================

set -Eeuo pipefail
trap '_on_error $LINENO' ERR
_on_error() {
  echo -e "\n${RED}[ERROR]${NC} Wipe script failed at line $1." >&2
  exit 1
}

# ── Source shared helpers ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# Final list of disks to wipe — populated interactively
DISKS_TO_WIPE=()

# =============================================================================
# DISK DETECTION
# =============================================================================

# Strips the partition suffix from a device path to return the raw disk.
#   nvme0n1p1  →  nvme0n1   (NVMe / eMMC use 'p' separator)
#   sda1       →  sda       (SATA/SCSI use trailing digit)
#   sr0        →  sr0       (optical drives ARE the disk — no suffix to strip)
_strip_partition() {
  local src="$1"
  if [[ "$src" =~ nvme|mmcblk ]]; then
    echo "${src%p[0-9]*}"
  elif [[ "$src" =~ /dev/sr ]]; then
    echo "$src"
  else
    echo "${src%[0-9]*}"
  fi
}

find_live_disk() {
  # Returns the raw disk device (e.g. /dev/sda) that the live ISO is running
  # from, so we can exclude it from the wipe list.
  local src
  src="$(findmnt -n -o SOURCE /run/archiso/bootmnt 2>/dev/null || true)"
  if [[ -n "$src" ]]; then
    _strip_partition "$src"
    return
  fi
  # Fallback: the device mounted at / (works on non-archiso live envs)
  src="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
  if [[ -n "$src" && "$src" != "overlay" && "$src" != "airootfs" ]]; then
    _strip_partition "$src"
    return
  fi
  echo ""
}

detect_disks() {
  local live_disk
  live_disk="$(find_live_disk)"
  [[ -n "$live_disk" ]] \
    && info "Live boot disk detected (will be excluded): ${live_disk}"

  local disks=()
  while IFS= read -r dev; do
    local path="/dev/${dev}"

    # Skip live disk
    [[ -n "$live_disk" && "$path" == "$live_disk" ]] && continue

    # Skip if any partition of this disk is currently mounted
    local mounted=false
    while IFS= read -r part; do
      if grep -q "^/dev/${part}" /proc/mounts 2>/dev/null; then
        mounted=true
        break
      fi
    done < <(lsblk -ln -o NAME "$path" 2>/dev/null | tail -n +2)
    if $mounted; then
      warn "Skipping $path — has mounted partitions."
      continue
    fi

    disks+=("$path")
  done < <(lsblk -dno NAME,TYPE,RO | awk '$2=="disk" && $3=="0" {print $1}')

  ((${#disks[@]} > 0)) && printf '%s\n' "${disks[@]}" || true
}

# =============================================================================
# DISK INFO TABLE
# =============================================================================

disk_info_table() {
  local disks=("$@")
  # SC2059: BOLD/NC are colour escapes that we deliberately interpolate into
  # the printf format string for ANSI colouring of the header row.
  # shellcheck disable=SC2059
  printf "\n  ${BOLD}%-5s  %-14s  %-8s  %-8s  %-28s  %s${NC}\n" \
    "Idx" "Device" "Size" "Type" "Model" "Serial"
  printf "  %s\n" "$(printf '─%.0s' {1..84})"
  local i=1
  local disk
  for disk in "${disks[@]}"; do
    local size model serial rota tran dtype
    size="$(lsblk -dno SIZE "$disk" 2>/dev/null | xargs || echo '?')"
    model="$(lsblk -dno MODEL "$disk" 2>/dev/null | xargs || echo 'unknown')"
    serial="$(lsblk -dno SERIAL "$disk" 2>/dev/null | xargs || echo '-')"
    rota="$(lsblk -dno ROTA "$disk" 2>/dev/null || echo '?')"
    tran="$(lsblk -dno TRAN "$disk" 2>/dev/null | xargs || echo '?')"
    if [[ "$tran" == "nvme" ]]; then
      dtype="NVMe"
    elif [[ "$rota" == "0" ]]; then
      dtype="SSD"
    elif [[ "$rota" == "1" ]]; then
      dtype="HDD"
    else dtype="?"; fi
    # shellcheck disable=SC2059  # see header printf above
    printf "  ${BOLD}%-5s${NC}  %-14s  %-8s  %-8s  %-28s  %s\n" \
      "[$i]" "$disk" "$size" "$dtype" "${model:0:28}" "$serial"
    ((i++))
  done
  echo ""
}

# =============================================================================
# INTERACTIVE DISK SELECTION
# =============================================================================

select_disks() {
  local all_disks=("$@")
  DISKS_TO_WIPE=("${all_disks[@]}")

  if [[ "${INSTALL_UNATTENDED:-0}" == "1" ]]; then
    info "Unattended mode — all detected disks selected for wiping" \
         "(no exclusions)."
    return
  fi

  echo -e "  ${BOLD}All detected disks will be wiped by default.${NC}"
  echo -e "  To ${YELLOW}EXCLUDE${NC} disks, enter their index" \
          "numbers (space-separated)."
  echo -e "  Press ${BOLD}Enter${NC} with no input to wipe" \
          "everything listed above."
  echo ""
  read -rp "  Exclude disks by index (e.g. '1 3'), or Enter to wipe all: " excl

  [[ -z "$excl" ]] && {
    info "All disks selected for wiping."
    return
  }

  local final=()
  local excl_arr
  read -ra excl_arr <<<"$excl"
  local i ex
  for i in "${!all_disks[@]}"; do
    local skip=false
    for ex in "${excl_arr[@]}"; do
      [[ "$ex" == "$((i + 1))" ]] && skip=true && break
    done
    if $skip; then
      warn "Excluding: ${all_disks[$i]}"
    else
      final+=("${all_disks[$i]}")
    fi
  done
  DISKS_TO_WIPE=("${final[@]}")
}

# =============================================================================
# FINAL CONFIRMATION
# =============================================================================

final_confirm() {
  echo ""
  echo -e "  ${RED}${BOLD}╔════════════════════════════════════════════╗${NC}"
  echo -e "  ${RED}${BOLD}║       !! POINT OF NO RETURN !!             ║${NC}"
  echo -e "  ${RED}${BOLD}║  Disks will be COMPLETELY and              ║${NC}"
  echo -e "  ${RED}${BOLD}║  IRREVERSIBLY ZERO-FILLED. ALL DATA LOST.  ║${NC}"
  echo -e "  ${RED}${BOLD}╚════════════════════════════════════════════╝${NC}"
  echo ""
  local disk
  for disk in "${DISKS_TO_WIPE[@]}"; do
    local size model
    size="$(lsblk -dno SIZE "$disk" 2>/dev/null | xargs || echo '?')"
    model="$(lsblk -dno MODEL "$disk" 2>/dev/null | xargs || echo 'unknown')"
    echo -e "    ${RED}✗${NC}  $disk  ($size  —  $model)"
  done
  echo ""
  if [[ "${INSTALL_UNATTENDED:-0}" == "1" ]]; then
    warn "Unattended mode — proceeding without WIPE confirmation."
    return
  fi

  echo -e "  ${BOLD}Type  ${RED}WIPE${NC}${BOLD}" \
          "(all caps) to confirm and begin:${NC}"
  read -rp "  > " _confirm
  [[ "$_confirm" == "WIPE" ]] ||
    error "Confirmation not received. No disks were modified."
}

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
  local log
  log="/tmp/wipe-$(basename "$disk").log"
  {
    echo "[$(date '+%T')] Starting: $disk"

    teardown_zfs "$disk"
    teardown_lvm "$disk"
    teardown_mdraid "$disk"

    # Clear all filesystem/partition signatures
    wipefs -af "$disk"

    # Destroy GPT and MBR partition tables
    sgdisk --zap-all "$disk"

    # Full zero-fill — dd exits non-zero when it hits end-of-disk ("no space
    # left"), which is expected and normal. We use `|| true` to suppress that.
    echo "[$(date '+%T')] Zero-filling $disk (this takes a while)..."
    dd if=/dev/zero of="$disk" bs=4M conv=fsync status=none 2>/dev/null || true

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

  declare -a pids disk_map
  local disk
  for disk in "${DISKS_TO_WIPE[@]}"; do
    info "Spawning wipe job: $disk"
    wipe_one_disk "$disk" &
    pids+=($!)
    disk_map+=("$disk")
  done

  echo ""
  info "${#DISKS_TO_WIPE[@]} disk(s) wiping in parallel."
  info "Logs: /tmp/wipe-<diskname>.log"
  echo ""

  # Live status ticker — updates every 5 seconds
  local all_done=false
  while ! $all_done; do
    all_done=true
    local line=""
    local i
    for i in "${!pids[@]}"; do
      local pid="${pids[$i]}"
      local disk_i="${disk_map[$i]}"
      if kill -0 "$pid" 2>/dev/null; then
        all_done=false
        line+="  ${YELLOW}●${NC} $(basename "$disk_i") running  "
      else
        # SC2015 fix: use explicit if/else instead of A && B || C, so the
        # branch chosen does not depend on whether B itself succeeded.
        if wait "$pid" 2>/dev/null; then
          line+="  ${GREEN}✔${NC} $(basename "$disk_i") done  "
        else
          line+="  ${YELLOW}!${NC} $(basename "$disk_i") check log  "
        fi
      fi
    done
    printf "\r%b" "$line"
    sleep 5
  done
  echo ""

  # Collect exit statuses — dd "no space" exit is normal, not an error
  local any_failed=false
  local i
  for i in "${!pids[@]}"; do
    wait "${pids[$i]}" 2>/dev/null || {
      local log
      log="/tmp/wipe-$(basename "${disk_map[$i]}").log"
      # Only flag as failure if the log doesn't end with "Done:"
      if ! grep -q "^.*Done:" "$log" 2>/dev/null; then
        warn "Wipe may have failed for ${disk_map[$i]} — check $log"
        any_failed=true
      fi
    }
  done
  $any_failed && warn "One or more wipes may need attention. Check logs above."
}

# =============================================================================
# SUMMARY
# =============================================================================

print_summary() {
  section "Wipe Complete"
  echo ""
  local disk
  for disk in "${DISKS_TO_WIPE[@]}"; do
    local log
    log="/tmp/wipe-$(basename "$disk").log"
    local last
    last="$(tail -1 "$log" 2>/dev/null || echo 'no log')"
    echo -e "  ${GREEN}✔${NC}  $disk   ${DIM}${last}${NC}"
  done
  echo ""
  echo -e "  ${BOLD}All selected disks have been zeroed.${NC}"
  echo ""
  echo -e "  ${BOLD}Next steps:${NC}"
  echo -e "  ${GREEN}✔${NC}  01-bootstrap-zfs.sh"
  echo -e "  ${GREEN}✔${NC}  02-wipe.sh"
  echo -e "  ${YELLOW}→${NC}  Edit install.json, then run 03-install.sh"
  echo ""
}

# =============================================================================
# MAIN
# =============================================================================

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y | --unattended)
        export INSTALL_UNATTENDED=1
        shift
        ;;
      -h | --help)
        echo "Usage: $(basename "$0") [-y|--unattended] [-h|--help]"
        echo ""
        echo "  -y, --unattended  Skip the disk-exclude prompt and the WIPE"
        echo "                    confirmation. Wipes every detected disk."
        echo "  -h, --help        Show this help and exit."
        exit 0
        ;;
      *)
        error "Unknown argument: $1"
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  echo -e "\n${CYAN}${BOLD}  Disk Wipe Utility${NC}"
  echo -e "${DIM}  Full zero-fill wipe — all detected physical disks${NC}"
  echo -e "${DIM}  ─────────────────────────────────────────────────${NC}\n"

  [[ $EUID -eq 0 ]] || error "Run as root."
  local cmd
  for cmd in lsblk wipefs sgdisk dd blockdev partprobe; do
    command -v "$cmd" &>/dev/null || error "Required tool not found: $cmd"
  done

  section "Detecting Disks"
  mapfile -t all_disks < <(detect_disks)
  ((${#all_disks[@]} > 0)) ||
    error "No eligible disks detected." \
          "Check connections and that no disk is mounted."

  info "Found ${#all_disks[@]} disk(s):"
  disk_info_table "${all_disks[@]}"

  section "Select Disks to Wipe"
  select_disks "${all_disks[@]}"
  ((${#DISKS_TO_WIPE[@]} > 0)) || {
    info "No disks selected. Nothing to do."
    exit 0
  }

  echo ""
  info "Disks selected for wiping (${#DISKS_TO_WIPE[@]}):"
  disk_info_table "${DISKS_TO_WIPE[@]}"

  final_confirm
  run_parallel_wipe
  print_summary
}

main "$@"
