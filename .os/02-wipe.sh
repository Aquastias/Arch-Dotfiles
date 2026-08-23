#!/usr/bin/env bash
# =============================================================================
# 02-wipe.sh — make-blank wipe (no secure-erase) of opted-in disks
# =============================================================================
# Leaves each wiped disk a blank slate: no partition table, no filesystem/ZFS/
# LVM/MD signatures. Include-based — nothing is wiped by default.
#
# Selection:
#   - Explicit DISK args (install.sh passes the install's target disks): wiped
#     exactly, no detection or selection.
#   - Standalone attended: detected disks listed, pick by index or `all`; Enter
#     cancels.
#   - Standalone unattended (-y) with no targets: no-op.
#
# Per disk: tear down ZFS/LVM/MD → wipefs → sgdisk --zap-all → device-aware
# clear (blkdiscard on SSD/NVMe, dd zero-pass on HDD) → second wipefs →
# blockdev --rereadpt. Disks already blank are probed and skipped
# (_wipe_probe_disk + lib/wipe/prior-state.sh). SSD/NVMe = seconds, HDD = hours;
# wiped in parallel, logged to /tmp/wipe-<disk>.log.
#
# Two confirmation gates (both skipped under unattended): [y/N] intent, then
# type WIPE. The Live-Medium Detector + a hard guard ensure the boot stick can
# never be erased. Honors INSTALL_UNATTENDED=1 from env or the -y flag.
# Run order: 01-bootstrap → 02-wipe → 03-install. See -h for usage.
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
  # Diagnostics go to stderr: stdout is captured verbatim as the disk list, so a
  # stray line there would be taken as a disk to wipe. Only device paths on
  # stdout. The live medium is excluded via the Live-Medium Detector
  # (lib/live-medium.sh), matched by whole-disk path.
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
  # SC2059: BOLD/NC colour escapes are interpolated into the format.
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

# parse_disk_selection INPUT DISK... — pure include-based selection, one path
# per line. Empty INPUT selects nothing (default-cancel).
parse_disk_selection() {
  local input="$1"; shift
  [[ -z "${input//[[:space:]]/}" ]] && return 0  # cancel → wipe nothing
  if [[ "${input,,}" == "all" ]]; then
    printf '%s\n' "$@"
    return 0
  fi
  # 1-based indices. Non-numeric / out-of-range tokens are skipped (never wipe a
  # disk you didn't name); a repeated index is emitted once (first-seen order).
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

# Interactive selection — only reached on a standalone attended run with no
# targets (main() handles the other paths). Enter cancels: nothing wiped.
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

# _wipe_probe_disk DISK — block-device I/O producing one prior-state fact line
# for the pure decider in lib/wipe/prior-state.sh:
#   <disk>|<is_live>|<sig>|<nparts>|<nonzero>
# sig/nparts (wipefs, lsblk) catch all structured data; nonzero samples 4 MiB at
# 33 offsets — heuristic, not an every-sector scan (a full multi-TB read would
# cost as much as the zero-fill it skips). Blank-by-decider is safe to install
# onto, so skipping is sound even if data hides between windows.
_wipe_probe_disk() {
  local disk="$1" is_live=0 sig="" nparts=0 nonzero=0

  is_live_medium "$disk" && is_live=1

  # Only probe a real block device. A resolved target set may name a disk absent
  # here (another host's disks); report it blank rather than run lsblk/dd,
  # which would fail under pipefail and trip the ERR trap. Can't wipe it anyway.
  if [[ -b "$disk" ]]; then
    # Presence only — wipefs output is multi-line, so collapse it to a token.
    [[ -n "$(wipefs "$disk" 2>/dev/null)" ]] && sig=present

    nparts="$(lsblk -ln -o NAME "$disk" 2>/dev/null | tail -n +2 | wc -l)"

    local size
    size="$(blockdev --getsize64 "$disk" 2>/dev/null || echo 0)"
    if ((size > 0)); then
      # 4 MiB window at 33 offsets (~132 MiB worst case); any non-zero byte
      # means the disk still holds data.
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
  fi

  printf '%s|%s|%s|%s|%s\n' "$disk" "$is_live" "$sig" "$nparts" "$nonzero"
}

# Drop already-zeroed disks from DISKS_TO_WIPE (reporting each skip): probe each
# target, then let the pure decider pick the set to wipe.
skip_zeroed_disks() {
  section "Checking for Already-Zeroed Disks"
  local disk kept=()
  mapfile -t kept < <(
    for disk in "${DISKS_TO_WIPE[@]}"; do _wipe_probe_disk "$disk"; done \
      | wipe_select_to_wipe
  )
  # Report each disk the decider dropped as blank. (Live-medium disks are
  # aborted by the hard guard earlier, so a drop here is blank.)
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

# Belt-and-suspenders over the Live-Medium Detector: if a live-medium disk ever
# reaches DISKS_TO_WIPE, abort before any teardown — the boot stick is never
# erased.
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
# A failed 03-install.sh leaves ZFS pools imported (altroot=/mnt) and datasets +
# ESP mounted under /mnt; detect_disks() then sees a mounted partition and SKIPS
# the disk you want to wipe. So clear that scratch state here, first. Scoped to
# /mnt and pools with altroot=/mnt (never the live system); unmount/export
# is non-destructive — no data erased, pools re-importable.

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

  # Clear any leftover /mnt install env from a failed run so the target disk
  # isn't excluded by detect_disks() as "mounted". No-op when /mnt is clean.
  reset_prior_install_state

  if ((${#TARGETS[@]} > 0)); then
    # Install-driven: wipe exactly the disks we were handed (resolved by the
    # Single Entry Point). No detection, no selection.
    section "Target Disks (install-driven)"
    DISKS_TO_WIPE=("${TARGETS[@]}")
    info "Wiping ${#DISKS_TO_WIPE[@]} install target disk(s):"
    disk_info_table "${DISKS_TO_WIPE[@]}"
  elif [[ "${INSTALL_UNATTENDED:-0}" == "1" ]]; then
    # Unattended with no targets: nothing to wipe. The old "wipe every detected
    # disk" default is intentionally gone.
    info "No target disks given. Nothing to wipe."
    exit 0
  else
    # Standalone attended: detect, show table, include-select (Enter cancels).
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
  # set — abort loudly before probing (the decider also drops it, but the loud
  # abort must win).
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
