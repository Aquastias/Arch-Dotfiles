#!/usr/bin/env bash
# =============================================================================
# lib/common.sh — Shared utilities
# =============================================================================
# Sourced by 03-install.sh before any other module.
# Provides: colour codes, output helpers, config accessors (cfg/cfgo),
#           interactive prompt helpers, and all shared global variables.
#
# GLOBALS DEFINED HERE (written by other modules, declared here for clarity):
#   INSTALL_MODE        "single" | "multi"
#   MOUNT_ROOT          /mnt (constant)
#   CONFIG_FILE         path to install.json (set by 03-install.sh)
#   SCRIPT_DIR          directory containing 03-install.sh (set by 03-install.sh)
#   PICK_RESULT         last result from pick_option()
#
# LAYOUT CONTRACT (Layout Module → consumers):
#   The active layout module (lib/layout-<mode>.sh) populates the LAYOUT_*
#   globals below. Consumers (chroot.sh, finalize.sh) read these instead of
#   the layout-private SINGLE_* / MULTI_* / OS_ESP_PARTS / STORAGE_PARTS,
#   so they don't need to know which mode is active.
#
#     LAYOUT_ESP_PARTS[]      Resolved ESP partition device paths. Index 0
#                             is the primary (mounted at /boot/efi). Length
#                             ≥ 1 after layout_partition() has run.
#     LAYOUT_OS_POOL_NAME     Resolved OS pool name (e.g. "rpool"). Set by
#                             layout_plan(); safe to read after planning.
#     LAYOUT_DATA_POOL_NAME   Resolved data pool name, or empty string when
#                             no data pool will be created.
# =============================================================================

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
#
# Usage: pick_option "Question" "option one text" "option two text" ...
pick_option() {
  local question="$1"
  shift
  local options=("$@")
  echo -e "\n${YELLOW}[?]${NC} ${question}"
  for i in "${!options[@]}"; do
    printf "    ${BOLD}%d)${NC} %s\n" "$((i + 1))" "${options[$i]}"
  done
  local choice
  while true; do
    read -rp "$(echo -e "${DIM}    Enter number [1-${#options[@]}]: ${NC}")" choice
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

# jsonc FILE
# Strips // line-comments from a JSONC file and emits plain JSON on stdout.
# Handles comments at end-of-line and on their own line.
# Safe for URLs — only matches // that are not inside a string value.
# (Simple heuristic: strips // not preceded by : or " on the same line segment)
jsonc() {
  sed \
    -e 's|[[:space:]]*//$||' \
    -e 's|[[:space:]]//[^"]*$||' \
    -e '/^[[:space:]]*\/\//d' \
    "$1" 2>/dev/null
}

# cfg PATH [LABEL]
# Required field — exits with a clear error if the field is missing or null.
cfg() {
  local v
  v="$(jsonc "$CONFIG_FILE" | jq -r "$1 // empty")"
  [[ -n "$v" ]] || error "Missing required config field: ${2:-$1}"
  echo "$v"
}

# cfgo PATH
# Optional field — returns empty string if the field is missing or null.
cfgo() { jsonc "$CONFIG_FILE" | jq -r "$1 // empty"; }

# ── Shared globals ────────────────────────────────────────────────────────────
# MOUNT_ROOT and CONFIG_FILE are set by 03-install.sh before sourcing modules.
# Declare here so all modules can reference them without re-declaring.

# shellcheck disable=SC2034 # set/read across sourced modules
INSTALL_MODE="" # "single" | "multi"  — set by detect_mode() in config.sh
# shellcheck disable=SC2034 # set/read across sourced modules
PICK_RESULT=""  # last pick_option() result

# ── Layout state record (populated by lib/layout-<mode>.sh) ───────────────────
# shellcheck disable=SC2034 # set by layout-*.sh, read by chroot.sh/finalize.sh
LAYOUT_ESP_PARTS=()
# shellcheck disable=SC2034
LAYOUT_OS_POOL_NAME=""
# shellcheck disable=SC2034
LAYOUT_DATA_POOL_NAME=""

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
