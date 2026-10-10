#!/usr/bin/env bash
# =============================================================================
# lib/common.sh — Shared utilities
# =============================================================================
# Sourced by 03-install.sh before any other module.
# Provides: colour codes, output helpers, config accessors (config_required/config_optional),
#           interactive prompt helpers.
#
# Cross-module globals and the layout contract: see lib/globals.sh.
# =============================================================================


# shellcheck source=./jsonc.sh
source "${BASH_SOURCE[0]%/*}/jsonc.sh"
# shellcheck source=./globals.sh
source "${BASH_SOURCE[0]%/*}/globals.sh"
# shellcheck source=./layout/state.sh
source "${BASH_SOURCE[0]%/*}/layout/state.sh"
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
# shellcheck disable=SC2034 # PICK_RESULT is the out-param, read by layout-*.sh
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

# ── Command utilities ─────────────────────────────────────────────────────────

# True if <cmd> resolves on PATH. Installer-world twin of Shell Stdlib's
# command_exists (one helper per world; see docs/agents/shell-commons.md).
command_exists() { command -v "$1" >/dev/null 2>&1; }

# Generic retry-with-backoff (ADR 0052). Runs the command; on failure sleeps the
# next backoff value and retries, up to <attempts> total tries. Returns the
# command's last exit status. `attempts` counts *total* tries, so the number of
# sleeps is attempts-1; backoff is a CSV of per-gap seconds (missing → 0). The
# bootstrap ladder calls `_retry 3 "3,10"` — one initial try plus two retries,
# sleeping 3s then 10s (~13s worst case per rung).
#   _retry <attempts> <backoff-csv> -- cmd [args...]
_retry() {
  local attempts="$1" backoff_csv="$2"; shift 2
  [[ "${1:-}" == "--" ]] && shift
  local -a backoff=()
  IFS=',' read -ra backoff <<< "$backoff_csv"
  local attempt=0 rc=0
  while :; do
    attempt=$((attempt + 1))
    # stderr markers: the Feature Audit folds a recovered attempt's errors
    # (ADR 0152); no error-shaped words, so the markers are never Findings
    echo "[ATTEMPT] $attempt/$attempts $1" >&2
    # `&& return 0 || rc=$?` captures the command's own status (an `if` around
    # it would swallow it) while staying set -e-safe.
    "$@" && return 0 || rc=$?
    (( attempt >= attempts )) && return "$rc"
    echo "[RETRY] attempt $attempt/$attempts of $1 returned $rc;" \
      "trying again" >&2
    sleep "${backoff[attempt-1]:-0}"
  done
}

# ── Config accessors ──────────────────────────────────────────────────────────
# Both functions require CONFIG_FILE to be set before use.

# config_required PATH [LABEL]
# Required field — exits with a clear error if the field is missing or null.
config_required() {
  local value
  value="$(jsonc_read_optional "$CONFIG_FILE" "$1")"
  [[ -n "$value" ]] || error "Missing required config field: ${2:-$1}"
  echo "$value"
}

# config_optional PATH
# Optional field — returns empty string if the field is missing or null.
config_optional() { jsonc_read_optional "$CONFIG_FILE" "$1"; }

# =============================================================================
# DISK UTILITIES (shared between layout modules)
# =============================================================================

part_name() {
  # Returns the full partition device path for a disk + partition number.
  # Stable /dev/disk symlinks use a '-part' suffix (udev), regardless of bus:
  #   /dev/disk/by-id/nvme-… + 1 → /dev/disk/by-id/nvme-…-part1
  # NVMe/eMMC kernel nodes use a 'p' separator:
  #   nvme0n1 + 1 → nvme0n1p1
  # SATA/SCSI kernel nodes do not:
  #   sda     + 1 → sda1
  local disk="$1" partition_number="$2"
  case "$disk" in
  /dev/disk/*)       echo "${disk}-part${partition_number}" ;;
  *nvme* | *mmcblk*) echo "${disk}p${partition_number}" ;;
  *)                 echo "${disk}${partition_number}" ;;
  esac
}

# ── Path helpers (ADR 0153) — one copy per world, never shared ──

# parent_directory <path> — the directory holding <path>, like dirname.
parent_directory() {
  local path="$1"
  while [[ "$path" == */ && "$path" != / ]]; do path="${path%/}"; done
  if [[ "$path" != */* ]]; then
    printf '.\n'
    return 0
  fi
  path="${path%/*}"
  while [[ "$path" == */ ]]; do path="${path%/}"; done
  printf '%s\n' "${path:-/}"
}

# base_name <path> [suffix] — the last part of <path>, like basename.
base_name() {
  local path="$1" suffix="${2:-}"
  while [[ "$path" == */ && "$path" != / ]]; do path="${path%/}"; done
  [[ "$path" == / ]] || path="${path##*/}"
  [[ -n "$suffix" && "$path" != "$suffix" ]] && path="${path%"$suffix"}"
  printf '%s\n' "$path"
}

# join_words — stdin's words joined by single spaces on one line (a trim that
# also folds lines), like `… | xargs` without its quote handling.
join_words() {
  awk '{ for (i = 1; i <= NF; i++) words = words (words == "" ? "" : " ") $i }
       END { print words }'
}
