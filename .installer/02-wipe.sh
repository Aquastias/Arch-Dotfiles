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
# (lib/wipe/probe.sh + lib/wipe/prior-state.sh). SSD/NVMe = seconds, HDD =
# hours; wiped in parallel, logged to /tmp/wipe-<disk>.log.
#
# Two confirmation gates (both skipped under unattended): [y/N] intent, then
# type WIPE. The Live-Medium Detector + a hard guard ensure the boot stick can
# never be erased. Honors INSTALL_UNATTENDED=1 from env or the -y flag.
# Run order: 01-bootstrap → 02-wipe → 03-install. See -h for usage.
# =============================================================================

set -Eeuo pipefail
trap '_on_error $LINENO' ERR
_on_error() {
  # Only the top-level shell reports: `set -E` fires this inside command
  # substitutions too, where an `exit` would kill a helper bash itself runs
  # without errexit (e.g. a counter `((n++))` from 0).
  (( BASH_SUBSHELL == 0 )) || return 0
  echo -e "\n${RED}[ERROR]${NC} Wipe script failed at line $1." >&2
  exit 1
}

# ── Source shared helpers ────────────────────────────────────────────────────
# (The stdlib is not loaded yet; a bare `bash 02-wipe.sh` has no slash.)
script_path="${BASH_SOURCE[0]}"
[[ "$script_path" == */* ]] || script_path="./$script_path"
SCRIPT_DIR="$(cd "${script_path%/*}" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/live-medium.sh
source "${SCRIPT_DIR}/lib/live-medium.sh"
# shellcheck source=lib/wipe/prior-state.sh
source "${SCRIPT_DIR}/lib/wipe/prior-state.sh"
# shellcheck source=lib/wipe/probe.sh
source "${SCRIPT_DIR}/lib/wipe/probe.sh"
# shellcheck source=lib/wipe/selection.sh
source "${SCRIPT_DIR}/lib/wipe/selection.sh"
# shellcheck source=lib/wipe/prior-install.sh
source "${SCRIPT_DIR}/lib/wipe/prior-install.sh"
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
# MAIN — the wipe, phase by phase
# =============================================================================

main() {
  parse_arguments "$@"
  print_banner
  check_prerequisites
  # Clear any leftover /mnt install env from a failed run so the target disk
  # isn't excluded by wipe_detect_disks as "mounted". No-op when /mnt is clean.
  wipe_reset_prior_install
  choose_disks
  # Hard guard first: never wipe the live medium, even if it reached the target
  # set — abort loudly before probing (the decider also drops it, but the loud
  # abort must win).
  assert_no_live_medium_targets
  wipe_skip_blank_disks
  show_disks_to_wipe
  confirm_wipe_intent
  final_confirm
  wipe_run_parallel
  print_summary
}

# =============================================================================
# PHASES
# =============================================================================

print_banner() {
  echo -e "\n${CYAN}${BOLD}  Disk Wipe Utility${NC}"
  echo -e "${DIM}  Make-blank wipe — only the disk(s) you select or pass${NC}"
  echo -e "${DIM}  ─────────────────────────────────────────────────${NC}\n"
}

check_prerequisites() {
  [[ $EUID -eq 0 ]] || error "Run as root."
  local command_name
  for command_name in lsblk wipefs sgdisk dd blockdev partprobe blkdiscard; do
    command_exists "$command_name" \
      || error "Required tool not found: $command_name"
  done
}

# choose_disks — fill DISKS_TO_WIPE, or exit when there is nothing to wipe.
choose_disks() {
  if ((${#TARGETS[@]} > 0)); then
    # Install-driven: wipe exactly the disks we were handed (resolved by the
    # Single Entry Point). No detection, no selection.
    section "Target Disks (install-driven)"
    DISKS_TO_WIPE=("${TARGETS[@]}")
    info "Wiping ${#DISKS_TO_WIPE[@]} install target disk(s):"
    wipe_print_disk_table "${DISKS_TO_WIPE[@]}"
  elif [[ "${INSTALL_UNATTENDED:-0}" == "1" ]]; then
    # Unattended with no targets: nothing to wipe. The old "wipe every detected
    # disk" default is intentionally gone.
    info "No target disks given. Nothing to wipe."
    exit 0
  else
    choose_disks_interactively
  fi
}

# Standalone attended: detect, show table, include-select (Enter cancels).
choose_disks_interactively() {
  section "Detecting Disks"
  local all_disks
  mapfile -t all_disks < <(wipe_detect_disks)
  ((${#all_disks[@]} > 0)) ||
    error "No eligible disks detected." \
          "Check connections and that no disk is mounted."

  info "Found ${#all_disks[@]} disk(s):"
  wipe_print_disk_table "${all_disks[@]}"

  section "Select Disks to Wipe"
  wipe_select_disks "${all_disks[@]}"
  ((${#DISKS_TO_WIPE[@]} > 0)) || {
    info "No disks selected. Nothing to do."
    exit 0
  }
}

# Belt-and-suspenders over the Live-Medium Detector: if a live-medium disk ever
# reaches DISKS_TO_WIPE, abort before any teardown — the boot stick is never
# erased.
assert_no_live_medium_targets() {
  local disk
  for disk in "${DISKS_TO_WIPE[@]}"; do
    if live_medium_contains_disk "$disk"; then
      error "Refusing to wipe ${disk}: it is the live install medium."
    fi
  done
}

show_disks_to_wipe() {
  ((${#DISKS_TO_WIPE[@]} > 0)) || {
    info "All selected disks are already zeroed. Nothing to do."
    exit 0
  }
  echo ""
  info "Disks selected for wiping (${#DISKS_TO_WIPE[@]}):"
  wipe_print_disk_table "${DISKS_TO_WIPE[@]}"
}

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
  local disk size model
  for disk in "${DISKS_TO_WIPE[@]}"; do
    size="$(lsblk -dno SIZE "$disk" 2>/dev/null | join_words || echo '?')"
    model="$(lsblk -dno MODEL "$disk" 2>/dev/null | join_words \
      || echo 'unknown')"
    echo -e "    ${RED}✗${NC}  $disk  ($size  —  $model)"
  done
  echo ""
  if [[ "${INSTALL_UNATTENDED:-0}" == "1" ]]; then
    warn "Unattended mode — proceeding without WIPE confirmation."
    return
  fi

  echo -e "  ${BOLD}Type  ${RED}WIPE${NC}${BOLD}" \
          "(all caps) to confirm and begin:${NC}"
  local confirmation
  read -rp "  > " confirmation
  [[ "$confirmation" == "WIPE" ]] ||
    error "Confirmation not received. No disks were modified."
}

print_summary() {
  section "Wipe Complete"
  echo ""
  local disk log last_line
  for disk in "${DISKS_TO_WIPE[@]}"; do
    log="/tmp/wipe-$(base_name "$disk").log"
    last_line="$(awk 'END { print }' "$log" 2>/dev/null || echo 'no log')"
    echo -e "  ${GREEN}✔${NC}  $disk   ${DIM}${last_line}${NC}"
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

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y | --unattended)
        export INSTALL_UNATTENDED=1
        shift
        ;;
      -h | --help)
        echo "Usage: $(base_name "$0") [-y|--unattended] [DISK...]"
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

# Execute only when run directly; when sourced (e.g. by bats) it won't auto-run.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
