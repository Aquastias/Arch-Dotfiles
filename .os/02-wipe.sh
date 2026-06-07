#!/usr/bin/env bash
# =============================================================================
# 02-wipe.sh
# =============================================================================
# PURPOSE:
#   Make-blank wipe of the disk(s) you opt into so they appear brand new —
#   no partition tables, no filesystem signatures, no ZFS labels, no LVM
#   metadata, no RAID superblocks. After this script each wiped disk is a blank
#   slate ready for the installer to partition from scratch.
#
# SELECTION MODEL (include-based, nothing wiped by default):
#   - Explicit targets: any positional DISK args are the exact disks to wipe;
#     detection + selection are skipped. install.sh resolves the install's
#     target disks (single .disk, or os_pool/storage_groups/data_pools) and
#     passes them here, so the wipe only ever touches disks the install uses.
#   - Standalone (no targets), attended: detected disks are listed and you
#     pick which to wipe by index (or `all`); Enter cancels (wipe nothing).
#   - Standalone (no targets), unattended (-y): nothing to wipe (safe no-op).
#
# WHAT IT DOES PER DISK (in order):
#   1. Tears down any ZFS pools using that disk (import → destroy)
#   2. Deactivates any LVM physical volumes / volume groups on that disk
#   3. Stops any MD-RAID arrays that include partitions on that disk
#   4. wipefs -af           — clears all filesystem/partition signatures
#   5. sgdisk --zap-all     — destroys GPT + MBR partition tables
#   6. device-aware clear   — blkdiscard (SSD/NVMe) or a dd zero-pass (HDD),
#                             routed by the Wipe-Method Selector; discard
#                             falls back to a zero-pass if unsupported
#   7. Second wipefs pass   — catches anything the clear may have re-written
#   8. blockdev --rereadpt  — tells the kernel to re-read the empty table
#
# DISK DETECTION (standalone path only):
#   Auto-detects all block devices of type "disk" via lsblk for the selection
#   table. Automatically SKIPS:
#     - The live USB/CD the system booted from
#     - Any disk with currently mounted partitions
#     - Loop devices, optical drives, RAM disks
#   The live-medium hard guard also refuses any explicitly-passed target that
#   is the install medium, so the boot stick can never be erased.
#
# ALREADY-ZEROED DISKS:
#   Before wiping, each selected disk is checked: if it carries no signatures,
#   no partition table, and samples clean of non-zero data, it is reported as
#   already blank and SKIPPED (no redundant zero-fill). See _wipe_probe_disk()
#   + the pure decider in lib/wipe/prior-state.sh.
#
# CONFIRMATION:
#   Two gates protect the wipe (both skipped under unattended mode):
#     1. "Do you wish to wipe the disk(s)?"  [y/N]
#     2. Type WIPE (all caps) at the point of no return.
#
# WIPE DEPTH:
#   Make-blank, not secure-erase (shred is never used). SSD/NVMe are cleared
#   with an instant blkdiscard; HDDs get a single dd zero-pass. All disks are
#   wiped IN PARALLEL to minimise total wall-clock time. Progress is logged to
#   /tmp/wipe-<diskname>.log.
#   Expect: SSDs/NVMe = seconds (discard), HDDs = hours (~130 MB/s, 1TB ≈ 2h).
#
# RUN ORDER:
#   1. 01-bootstrap-zfs.sh
#   2. 02-wipe.sh            ← you are here
#   3. 03-install.sh
#
# USAGE:
#   chmod +x 02-wipe.sh
#   ./02-wipe.sh                      # interactive include-based selection
#   ./02-wipe.sh /dev/sda /dev/sdb    # wipe exactly these disks
#   ./02-wipe.sh -y /dev/sda          # unattended, explicit target, no prompts
#   ./02-wipe.sh -y                   # unattended, no target → nothing to wipe
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
# shellcheck source=lib/live-medium.sh
source "${SCRIPT_DIR}/lib/live-medium.sh"
# shellcheck source=lib/wipe/prior-state.sh
source "${SCRIPT_DIR}/lib/wipe/prior-state.sh"
# execute.sh guard-sources method.sh + progress.sh.
# shellcheck source=lib/wipe/execute.sh
source "${SCRIPT_DIR}/lib/wipe/execute.sh"

# Final list of disks to wipe — populated from explicit targets or selection.
DISKS_TO_WIPE=()

# Explicit target disks passed as positional args (e.g. by install.sh, which
# resolves the install's target disks from the config). When non-empty, these
# are the exact disks to wipe and disk detection + interactive selection are
# skipped — the wipe stays config-agnostic, touching only what it was handed.
TARGETS=()

# =============================================================================
# DISK DETECTION
# =============================================================================

detect_disks() {
  # Diagnostics go to stderr: this function's stdout is captured verbatim as the
  # disk list (`mapfile -t all_disks < <(detect_disks)`), so any info/warn line
  # on stdout would be mistaken for a disk to wipe (and wipe_one_disk fails on
  # it). Only device paths may reach stdout here.
  #
  # The live medium is excluded via the multi-signal Live-Medium Detector
  # (lib/live-medium.sh) — boot-mount parent disk, iso9660, ARCH_* label —
  # resolved once here and matched by whole-disk path. Robust on label/uuid
  # boot sources and on copytoram boots where the USB is unmounted.
  local live_set
  live_set="$(live_medium_disks)"
  [[ -n "$live_set" ]] \
    && info "Live medium detected (excluded): $(echo "$live_set" | xargs)" >&2

  local disks=()
  while IFS= read -r dev; do
    local path="/dev/${dev}"

    # Skip the live medium.
    grep -qxF "$path" <<<"$live_set" && continue

    # Skip if any partition of this disk is currently mounted
    local mounted=false
    while IFS= read -r part; do
      if grep -q "^/dev/${part}" /proc/mounts 2>/dev/null; then
        mounted=true
        break
      fi
    done < <(lsblk -ln -o NAME "$path" 2>/dev/null | tail -n +2)
    if $mounted; then
      warn "Skipping $path — has mounted partitions." >&2
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

# parse_disk_selection INPUT DISK... — pure include-based selection.
# Emits the included device paths (one per line). Empty INPUT selects nothing
# (the default-cancel: wipe nothing). Other rules are added per test below.
parse_disk_selection() {
  local input="$1"; shift
  [[ -z "${input//[[:space:]]/}" ]] && return 0  # cancel → wipe nothing
  if [[ "${input,,}" == "all" ]]; then
    printf '%s\n' "$@"
    return 0
  fi
  # 1-based indices into the disk list. Non-numeric / out-of-range tokens are
  # skipped (never wipe a disk you didn't name); a repeated index is emitted
  # once (preserve first-seen order) so a disk can't be wiped twice.
  local all=("$@") tok seen=() out=() s dup
  for tok in $input; do
    [[ "$tok" =~ ^[0-9]+$ ]] || continue
    (( tok >= 1 && tok <= ${#all[@]} )) || continue
    dup=false
    for s in "${seen[@]}"; do [[ "$s" == "$tok" ]] && { dup=true; break; }; done
    $dup && continue
    seen+=("$tok")
    out+=("${all[$((tok - 1))]}")
  done
  ((${#out[@]})) && printf '%s\n' "${out[@]}" || true
}

# Interactive include-based selection. Only reached on a standalone, attended
# run with no explicit targets — main() handles the install-driven (explicit
# targets) and unattended (no-op) paths before this. The default is to wipe
# NOTHING: Enter cancels.
select_disks() {
  local all_disks=("$@")
  echo -e "  ${BOLD}Select the disk(s) to wipe.${NC}"
  echo -e "  Enter the index number(s) to wipe (space-separated), or" \
          "${BOLD}all${NC}."
  echo -e "  Press ${BOLD}Enter${NC} with no input to" \
          "${YELLOW}cancel${NC} — nothing is wiped by default."
  echo ""
  local sel
  read -rp "  Wipe which disk(s)? (e.g. '1 3', 'all', Enter to cancel): " sel
  mapfile -t DISKS_TO_WIPE < <(parse_disk_selection "$sel" "${all_disks[@]}")
}

# =============================================================================
# ALREADY-ZEROED DETECTION
# =============================================================================

# _wipe_probe_disk DISK — block-device I/O that produces one prior-state fact
# line for the pure decider in lib/wipe/prior-state.sh:
#   <disk>|<is_live>|<sig>|<nparts>|<nonzero>
#   1. Any filesystem/partition signature (wipefs)  → sig non-empty
#   2. Any child partitions (lsblk)                 → nparts > 0
#   3. Sample 4 MiB windows at 33 evenly-spaced
#      offsets; any non-zero byte                   → nonzero=1
# Steps 1-2 catch all *structured* data (filesystems, partition tables,
# LVM/MD/ZFS labels). Step 3 catches gross leftover data but is heuristic —
# not an exhaustive every-sector scan, since a full read of a multi-TB disk
# would cost as much as the zero-fill it is meant to skip. A disk reported
# blank by the decider is safe to install onto as-is, so skipping its
# zero-fill is sound even if unstructured data hides between sample windows.
_wipe_probe_disk() {
  local disk="$1" is_live=0 sig="" nparts=0 nonzero=0

  is_live_medium "$disk" && is_live=1

  # Presence only — wipefs output is multi-line, so collapse it to a token.
  [[ -n "$(wipefs "$disk" 2>/dev/null)" ]] && sig=present

  nparts="$(lsblk -ln -o NAME "$disk" 2>/dev/null | tail -n +2 | wc -l)"

  local size
  size="$(blockdev --getsize64 "$disk" 2>/dev/null || echo 0)"
  if ((size > 0)); then
    # Read a 4 MiB window at 33 evenly-spaced offsets (~132 MiB worst case).
    # Any non-zero byte in any window means the disk still holds data.
    local chunk=$((4 * 1024 * 1024))
    local windows=32
    local step=$((size > chunk ? (size - chunk) / windows : 0))
    local i off nz
    for ((i = 0; i <= windows; i++)); do
      off=$((i * step))
      ((off > size - chunk)) && off=$((size > chunk ? size - chunk : 0))
      nz="$(dd if="$disk" bs="$chunk" count=1 skip="$off" \
        iflag=skip_bytes status=none 2>/dev/null | tr -d '\0' | wc -c)"
      ((nz > 0)) && { nonzero=1; break; }
    done
  fi

  printf '%s|%s|%s|%s|%s\n' "$disk" "$is_live" "$sig" "$nparts" "$nonzero"
}

# Drops already-zeroed disks from DISKS_TO_WIPE, reporting each skip. Probes
# each target (I/O), then lets the pure decider pick the set to wipe.
skip_zeroed_disks() {
  section "Checking for Already-Zeroed Disks"
  local disk kept=()
  mapfile -t kept < <(
    for disk in "${DISKS_TO_WIPE[@]}"; do _wipe_probe_disk "$disk"; done \
      | wipe_select_to_wipe
  )
  # Report each disk the decider dropped as already blank. (Live-medium disks
  # are aborted by the hard guard before this point, so a drop here is blank.)
  local k in_kept
  for disk in "${DISKS_TO_WIPE[@]}"; do
    in_kept=false
    for k in "${kept[@]}"; do [[ "$k" == "$disk" ]] && { in_kept=true; break; }; done
    $in_kept || info "Skipping $disk — already blank/zeroed (no wipe needed)."
  done
  DISKS_TO_WIPE=("${kept[@]}")
}

# =============================================================================
# LIVE-MEDIUM HARD GUARD
# =============================================================================

# Belt-and-suspenders over the Live-Medium Detector: even if a live-medium disk
# somehow reaches DISKS_TO_WIPE (e.g. a future caller passing targets in), abort
# before any teardown so the boot stick can never be erased.
assert_no_live_medium_targets() {
  local disk
  for disk in "${DISKS_TO_WIPE[@]}"; do
    if is_live_medium "$disk"; then
      error "Refusing to wipe ${disk}: it is the live install medium."
    fi
  done
}

# =============================================================================
# CONFIRMATION
# =============================================================================

# First gate: a plain yes/no intent check before the point of no return.
confirm_wipe_intent() {
  if [[ "${INSTALL_UNATTENDED:-0}" == "1" ]]; then
    info "Unattended mode — wipe intent assumed: yes."
    return
  fi
  echo ""
  echo -e "  ${BOLD}Do you wish to wipe the disk(s) listed above?${NC}"
  local reply
  read -rp "  Wipe these disk(s)? [y/N]: " reply
  case "$reply" in
    [yY] | [yY][eE][sS])
      info "Proceeding to final confirmation."
      ;;
    *)
      info "Wipe declined. No disks were modified."
      exit 0
      ;;
  esac
}

# Second gate: type WIPE at the point of no return.
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
# PRIOR INSTALL STATE RESET  (runs before disk detection)
# =============================================================================
# A failed/aborted 03-install.sh leaves the target's ZFS pools imported with
# altroot=/mnt and the datasets + ESP mounted under /mnt. detect_disks() then
# sees a mounted partition (the ESP at /mnt/boot/efi) and SKIPS the very disk
# you want to wipe — "No eligible disks". teardown_zfs() can't help: it runs
# per-disk, AFTER detection has already excluded the disk. So clear that
# scratch state here, first.
#
# Scoped strictly to /mnt (the installer's mountpoint) and pools whose altroot
# is /mnt — never the live system, which lives at '/'. Unmounting/exporting is
# non-destructive: no disk data is erased, pools can be re-imported.

# Injectable seams (overridden in tests).
_wipe_mounts_under_mnt() {
  findmnt -rno TARGET 2>/dev/null | grep -E '^/mnt(/|$)' || true
}
_wipe_pools_altroot_mnt() {
  command -v zpool &>/dev/null || return 0
  zpool list -H -o name,altroot 2>/dev/null \
    | awk '$2 ~ /^\/mnt(\/|$)/ {print $1}'
}

# Returns 0 if a previous-install scratch state is present at /mnt.
wipe_prior_state_present() {
  [[ -n "$(_wipe_mounts_under_mnt)" ]] && return 0
  [[ -n "$(_wipe_pools_altroot_mnt)" ]] && return 0
  return 1
}

reset_prior_install_state() {
  wipe_prior_state_present || return 0

  section "Previous Install Environment Detected"
  local _mounts _pools _line
  _mounts="$(_wipe_mounts_under_mnt)"
  _pools="$(_wipe_pools_altroot_mnt | xargs || true)"
  if [[ -n "$_mounts" ]]; then
    warn "Mounted under /mnt:"
    while IFS= read -r _line; do
      [[ -n "$_line" ]] && echo "      ${_line}"
    done <<<"$_mounts"
  fi
  [[ -n "$_pools" ]] && warn "Imported pool(s) with altroot=/mnt: ${_pools}"

  if [[ "${INSTALL_UNATTENDED:-0}" != "1" ]]; then
    echo ""
    local reply
    read -rp "  Tear down this /mnt install env so the disk is wipeable? [y/N]: " \
      reply
    case "$reply" in
      [yY] | [yY][eE][sS]) ;;
      *) warn "Left /mnt state intact — the target disk will stay excluded."
         return 0 ;;
    esac
  fi

  # 1. swapoff any swap backed by a zvol (e.g. /dev/zvol/rpool/swap).
  if command -v swapon &>/dev/null; then
    local _sw
    while IFS= read -r _sw; do
      [[ -n "$_sw" ]] && { swapoff "$_sw" 2>/dev/null || true; }
    done < <(swapon --show=NAME --noheadings 2>/dev/null \
             | grep '^/dev/zvol/' || true)
  fi
  # 2. Unmount the whole /mnt tree (ESP + datasets); lazy fallback for busy.
  umount -R /mnt 2>/dev/null || umount -Rl /mnt 2>/dev/null || true
  # 3. Export the /mnt-scoped pools (forced fallback) to release the disk.
  local _pool
  while IFS= read -r _pool; do
    [[ -z "$_pool" ]] && continue
    warn "Exporting pool '${_pool}'"
    zpool export "$_pool" 2>/dev/null \
      || zpool export -f "$_pool" 2>/dev/null || true
  done < <(_wipe_pools_altroot_mnt)

  if wipe_prior_state_present; then
    warn "Some /mnt state remains — inspect: mount | grep /mnt ; zpool list"
  else
    info "Previous install env cleared — disk is now wipeable."
  fi
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
        echo "Usage: $(basename "$0") [-y|--unattended] [DISK...]"
        echo ""
        echo "  DISK...           Explicit target disk(s) to wipe (e.g."
        echo "                    /dev/sda). When given, disk detection and"
        echo "                    interactive selection are skipped — only"
        echo "                    these disks are wiped. install.sh passes the"
        echo "                    install's target disks here."
        echo "  -y, --unattended  Skip the selection prompt and both wipe"
        echo "                    confirmations. With no DISK given there is"
        echo "                    nothing to wipe (safe no-op)."
        echo "  -h, --help        Show this help and exit."
        exit 0
        ;;
      -*)
        error "Unknown argument: $1"
        ;;
      *)
        TARGETS+=("$1")
        shift
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  echo -e "\n${CYAN}${BOLD}  Disk Wipe Utility${NC}"
  echo -e "${DIM}  Make-blank wipe — only the disk(s) you select or pass${NC}"
  echo -e "${DIM}  ─────────────────────────────────────────────────${NC}\n"

  [[ $EUID -eq 0 ]] || error "Run as root."
  local cmd
  for cmd in lsblk wipefs sgdisk dd blockdev partprobe blkdiscard; do
    command -v "$cmd" &>/dev/null || error "Required tool not found: $cmd"
  done

  # Clear any leftover /mnt install env from a failed run, so the target disk
  # isn't excluded by detect_disks() as "mounted". No-op when /mnt is clean.
  reset_prior_install_state

  if ((${#TARGETS[@]} > 0)); then
    # Install-driven: wipe exactly the disks we were handed (resolved by the
    # Single Entry Point from the Install Config). No detection, no selection.
    section "Target Disks (install-driven)"
    DISKS_TO_WIPE=("${TARGETS[@]}")
    info "Wiping ${#DISKS_TO_WIPE[@]} install target disk(s):"
    disk_info_table "${DISKS_TO_WIPE[@]}"
  elif [[ "${INSTALL_UNATTENDED:-0}" == "1" ]]; then
    # Unattended with no explicit targets: nothing to wipe (safe no-op). The
    # old "wipe every detected disk" default is intentionally gone.
    info "No target disks given. Nothing to wipe."
    exit 0
  else
    # Standalone, attended: detect, show the table, include-select (Enter
    # cancels — nothing is wiped by default).
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
  fi

  # Hard guard first: never wipe the live medium, even if it reached the target
  # set — abort loudly before any probing. (The pure prior-state decider also
  # drops it as belt-and-suspenders, but the loud abort must win here.)
  assert_no_live_medium_targets

  # Drop disks that are already blank — no point zero-filling them again.
  skip_zeroed_disks
  ((${#DISKS_TO_WIPE[@]} > 0)) || {
    info "All selected disks are already zeroed. Nothing to do."
    exit 0
  }

  echo ""
  info "Disks selected for wiping (${#DISKS_TO_WIPE[@]}):"
  disk_info_table "${DISKS_TO_WIPE[@]}"

  confirm_wipe_intent
  final_confirm
  run_parallel_wipe
  print_summary
}

# Execute only when run directly; when sourced (e.g. by bats) it won't auto-run.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
