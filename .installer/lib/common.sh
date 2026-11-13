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
  [[ "$ans" == [yY] ]] || error "Aborted by user."
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
    PICK_RESULT="$(first_word "${options[0]}")"
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
      PICK_RESULT="$(first_word "${options[$((choice - 1))]}")"
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
  # One backoff value per line, split at the commas.
  mapfile -t backoff < <(printf '%s\n' "$backoff_csv" | tr ',' '\n')
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
  # Kernel nodes whose name ends in a digit use a 'p' separator (the kernel's
  # rule — NVMe, eMMC, loop, nbd, md):
  #   nvme0n1 + 1 → nvme0n1p1
  # Names ending in a letter do not (SATA/SCSI, virtio, xen):
  #   sda     + 1 → sda1
  local disk="$1" partition_number="$2"
  case "$disk" in
  /dev/disk/*)       echo "${disk}-part${partition_number}" ;;
  *[0-9])            echo "${disk}p${partition_number}" ;;
  *)                 echo "${disk}${partition_number}" ;;
  esac
}

# first_word <text> — the text's first word (leading spaces skipped).
first_word() {
  local word _rest
  read -r word _rest < <(printf '%s\n' "$1")
  printf '%s\n' "$word"
}

# join_list — stdin's non-blank lines joined by ", " on one line ("a, b, c").
join_list() {
  local list="" line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    list+="${list:+, }${line}"
  done
  printf '%s\n' "$list"
}

# join_words — stdin's words joined by single spaces on one line (a trim
# that also folds lines). "${words[*]}" joins an array with spaces.
join_words() {
  local -a lines=() words=() line_words=()
  local line
  mapfile -t lines
  for line in "${lines[@]}"; do
    read -ra line_words < <(printf '%s\n' "$line")
    words+=("${line_words[@]}")
  done
  printf '%s\n' "${words[*]}"
}

# text_before <text> <separator> — the text before the first separator; the
# whole text when the separator is absent.
# shellcheck disable=SC2016 # a jq program, not shell
text_before() {
  local first_piece='$text | split($separator)[0] // ""'
  # The first piece of the text split on the separator.
  jq -r -n --arg text "$1" --arg separator "$2" "$first_piece"
}

# text_after <text> <separator> — the text after the first separator; the
# whole text when the separator is absent.
# shellcheck disable=SC2016 # a jq program, not shell
text_after() {
  local after_first='$text | split($separator)'
  after_first+=' | if length > 1 then .[1:] else . end | join($separator)'
  # Every piece but the first, joined back with the separator.
  jq -r -n --arg text "$1" --arg separator "$2" "$after_first"
}

# text_after_last <text> <separator> — the text after the last separator; the
# whole text when the separator is absent.
# shellcheck disable=SC2016 # a jq program, not shell
text_after_last() {
  local last_piece='$text | split($separator)[-1] // ""'
  # The last piece of the text split on the separator.
  jq -r -n --arg text "$1" --arg separator "$2" "$last_piece"
}

# json_string_array <text>… — the arguments as a compact JSON array of
# strings, in order: json_string_array a 'b c' → ["a","b c"].
json_string_array() {
  local json='[]' text
  for text in "$@"; do
    # The array so far, with this string added at the end.
    json="$(jq -c -n --argjson array "$json" --arg text "$text" \
      '$array + [$text]')"
  done
  printf '%s\n' "$json"
}
