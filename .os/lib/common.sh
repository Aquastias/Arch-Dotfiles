#!/usr/bin/env bash
# =============================================================================
# lib/common.sh — Shared utilities
# =============================================================================
# Sourced by 03-install.sh before any other module.
# Provides: colour codes, output helpers, config accessors (cfg/cfgo),
#           interactive prompt helpers.
#
# Cross-module globals and the layout contract: see lib/globals.sh.
# =============================================================================


# shellcheck source=./jsonc.sh
source "${BASH_SOURCE[0]%/*}/jsonc.sh"
# shellcheck source=./globals.sh
source "${BASH_SOURCE[0]%/*}/globals.sh"
# ── Colour codes ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Output helpers ────────────────────────────────────────────────────────────

info() { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
  exit 1
}
section() { echo -e "\n${CYAN}${BOLD}━━━  $*  ━━━${NC}"; }

# Prompts [y/N]; errors (exits) if the user does not confirm.
# Honors INSTALL_UNATTENDED=1 — auto-accepts every prompt with a log line.
confirm() {
  if [[ "${INSTALL_UNATTENDED:-0}" == "1" ]]; then
    info "Auto-confirmed (unattended): $*"
    return
  fi
  local ans
  read -rp "$(echo -e "${YELLOW}[?]${NC} $* [y/N]: ")" ans
  [[ "${ans,,}" == "y" ]] || error "Aborted by user."
}

# Displays a numbered menu and sets PICK_RESULT to the first word of the
# chosen entry. Loops until a valid number is entered.
# Honors INSTALL_UNATTENDED=1 — auto-selects option 1 with a log line.
#
# Usage: pick_option "Question" "option one text" "option two text" ...
pick_option() {
  local question="$1"
  shift
  local options=("$@")

  if [[ "${INSTALL_UNATTENDED:-0}" == "1" ]]; then
    PICK_RESULT="$(echo "${options[0]}" | awk '{print $1}')"
    info "Auto-picked option 1 (unattended): ${options[0]}"
    return
  fi

  echo -e "\n${YELLOW}[?]${NC} ${question}"
  for i in "${!options[@]}"; do
    printf "    ${BOLD}%d)${NC} %s\n" "$((i + 1))" "${options[$i]}"
  done
  local choice
  while true; do
    read -rp \
      "$(echo -e "${DIM}    Enter number [1-${#options[@]}]: ${NC}")" \
      choice
    if [[ "$choice" =~ ^[0-9]+$ ]] &&
      ((choice >= 1 && choice <= ${#options[@]})); then
      PICK_RESULT="$(echo "${options[$((choice - 1))]}" | awk '{print $1}')"
      return
    fi
    echo -e "    ${RED}Invalid.${NC} Enter 1–${#options[@]}."
  done
}

# ── Config accessors ──────────────────────────────────────────────────────────
# Both functions require CONFIG_FILE to be set before use.

# cfg PATH [LABEL]
# Required field — exits with a clear error if the field is missing or null.
cfg() {
  local v
  v="$(jsonc_read_opt "$CONFIG_FILE" "$1")"
  [[ -n "$v" ]] || error "Missing required config field: ${2:-$1}"
  echo "$v"
}

# cfgo PATH
# Optional field — returns empty string if the field is missing or null.
cfgo() { jsonc_read_opt "$CONFIG_FILE" "$1"; }

# =============================================================================
# DISK UTILITIES (shared between layout modules)
# =============================================================================

part_name() {
  # Returns the full partition device path for a disk + partition number.
  # NVMe/eMMC use a 'p' separator: nvme0n1 + 1 → nvme0n1p1
  # SATA/SCSI do not:             sda     + 1 → sda1
  local disk="$1" num="$2"
  [[ "$disk" =~ nvme|mmcblk ]] && echo "${disk}p${num}" || echo "${disk}${num}"
}
