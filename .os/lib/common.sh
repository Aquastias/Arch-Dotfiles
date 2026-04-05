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
# =============================================================================

# ── Colour codes ──────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# ── Output helpers ────────────────────────────────────────────────────────────

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
section() { echo -e "\n${CYAN}${BOLD}━━━  $*  ━━━${NC}"; }

# Prompts [y/N]; errors (exits) if the user does not confirm.
confirm() {
    local ans
    read -rp "$(echo -e "${YELLOW}[?]${NC} $* [y/N]: ")" ans
    [[ "${ans,,}" == "y" ]] || error "Aborted by user."
}

# Displays a numbered menu and sets PICK_RESULT to the first word of the
# chosen entry. Loops until a valid number is entered.
#
# Usage: pick_option "Question" "option one text" "option two text" ...
pick_option() {
    local question="$1"; shift
    local options=("$@")
    echo -e "\n${YELLOW}[?]${NC} ${question}"
    for i in "${!options[@]}"; do
        printf "    ${BOLD}%d)${NC} %s\n" "$((i+1))" "${options[$i]}"
    done
    local choice
    while true; do
        read -rp "$(echo -e "${DIM}    Enter number [1-${#options[@]}]: ${NC}")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && \
           (( choice >= 1 && choice <= ${#options[@]} )); then
            PICK_RESULT="$(echo "${options[$((choice-1))]}" | awk '{print $1}')"
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
    local v; v="$(jq -r "$1 // empty" "$CONFIG_FILE")"
    [[ -n "$v" ]] || error "Missing required config field: ${2:-$1}"
    echo "$v"
}

# cfgo PATH
# Optional field — returns empty string if the field is missing or null.
cfgo() { jq -r "$1 // empty" "$CONFIG_FILE"; }

# ── Shared globals ────────────────────────────────────────────────────────────
# MOUNT_ROOT and CONFIG_FILE are set by 03-install.sh before sourcing modules.
# Declare here so all modules can reference them without re-declaring.

INSTALL_MODE=""   # "single" | "multi"  — set by detect_mode() in config.sh
PICK_RESULT=""    # last pick_option() result
