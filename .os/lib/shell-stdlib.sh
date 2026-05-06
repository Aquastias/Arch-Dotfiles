#!/usr/bin/env bash
# =============================================================================
# shell-stdlib.sh — unified shell utility library
# =============================================================================
# Single entry point replacing the 8 individual commons files.
# Source this file once; all functions are available immediately.
#
# Usage in install scripts:
#   source "$SHELL_COMMONS/shell-stdlib.sh"
# =============================================================================

# =============================================================================
# STRINGS
# =============================================================================

function string_contains() {
  local -r haystack="$1"
  local -r needle="$2"
  [[ "$haystack" == *"$needle"* ]]
}

function string_multiline_contains() {
  local -r haystack="$1"
  local -r needle="$2"
  echo "$haystack" | grep -q "$needle"
}

function string_to_uppercase() {
  local -r str="$1"
  echo "$str" | awk '{print toupper($0)}'
}

function string_strip_prefix() {
  local -r str="$1"
  local -r prefix="$2"
  # SC2295: prefix is data, not a glob pattern — quote so '*' / '?' are literal.
  echo "${str#"$prefix"}"
}

function string_strip_suffix() {
  local -r str="$1"
  local -r suffix="$2"
  # SC2295: suffix is data, not a glob pattern — quote so '*' / '?' are literal.
  echo "${str%"$suffix"}"
}

function string_is_empty_or_null() {
  local -r response="$1"
  [[ -z "$response" || "$response" == "null" ]]
}

function string_substr() {
  local -r str="$1"
  local -r start="$2"
  local end="$3"

  if [[ "$start" -lt 0 || "$end" -lt 0 ]]; then
    echo "Error: string_substr: start and end must be >= 0." >&2
    exit 1
  fi
  if [[ "$start" -gt "$end" ]]; then
    echo "Error: string_substr: start must be <= end." >&2
    exit 1
  fi
  [[ -z "$end" ]] && end="${#str}"
  echo "${str:$start:$end}"
}

# print_status [type] [message]
# type: success | warning | error | info | custom <color> | (omit for plain)
function print_status() {
  local type="$1"
  shift

  local message color_name

  if [[ -z "$type" ]]; then
    echo "$*"
    return
  fi

  if [[ "$type" == "custom" ]]; then
    color_name="$1"; shift
    message="$*"
  else
    message="$*"
  fi

  local RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m'
  local BLUE='\033[0;34m' MAGENTA='\033[0;35m' CYAN='\033[0;36m'
  local WHITE='\033[0;37m' NC='\033[0m'

  local color_code="" prefix=""

  case "$type" in
  success) color_code="$GREEN";   prefix="[SUCCESS]" ;;
  warning) color_code="$YELLOW";  prefix="[WARNING]" ;;
  error)   color_code="$RED";     prefix="[ERROR]"   ;;
  info)    color_code="$BLUE";    prefix="[INFO]"    ;;
  custom)
    case "$color_name" in
    red)     color_code="$RED"     ;;
    green)   color_code="$GREEN"   ;;
    yellow)  color_code="$YELLOW"  ;;
    blue)    color_code="$BLUE"    ;;
    magenta) color_code="$MAGENTA" ;;
    cyan)    color_code="$CYAN"    ;;
    white)   color_code="$WHITE"   ;;
    *)       color_code="$NC"      ;;
    esac
    ;;
  *) color_code="$NC" ;;
  esac

  echo -e "${color_code}${prefix:+$prefix }$message${NC}"
}

# =============================================================================
# ARRAYS
# =============================================================================

function array_contains() {
  local -r needle="$1"
  shift
  local -ra haystack=("$@")
  local item
  for item in "${haystack[@]}"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

function array_split() {
  local -r separator="$1"
  local -r str="$2"
  local -a ary=()
  IFS="$separator" read -r -a ary <<<"$str"
  echo "${ary[*]}"
}

function array_join() {
  local -r separator="$1"
  shift
  local -ar values=("$@")
  local out=""
  local i
  for ((i = 0; i < ${#values[@]}; i++)); do
    [[ "$i" -gt 0 ]] && out="${out}${separator}"
    out="${out}${values[i]}"
  done
  echo -n "$out"
}

function array_prepend() {
  local -r prefix="$1"
  shift 1
  local -ar ary=("$@")
  local -a updated_ary
  updated_ary=("${ary[@]/#/$prefix}")
  echo "${updated_ary[*]}"
}

# =============================================================================
# COMMANDS
# =============================================================================

function command_exists() {
  command -v "$1" >/dev/null 2>&1
}

function check_command() {
  if ! command_exists "$1"; then
    echo "Error: '$1' command not found" >&2
    exit 127
  fi
}

function command_output_contains() {
  local command_output
  # shellcheck disable=SC2294
  # Callers pass arbitrary command strings (e.g. "lsblk -dno NAME") that may
  # contain pipes/options; eval is required for shell-string semantics.
  command_output=$(eval "$1")
  string_contains "$command_output" "$2"
}

# =============================================================================
# PERMISSIONS
# =============================================================================

function check_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "This script must be run as root" >&2
    exit 1
  fi
}

function make_env_bash_scripts_executable() {
  local target_dir="${1:-.}"
  while IFS= read -r -d '' file; do
    if head -n 1 "$file" | grep -q '^#!/usr/bin/env bash$'; then
      chmod +x "$file"
      echo "Made executable: $file"
    fi
  done < <(find "$target_dir" -type f -print0)
  echo "Finished setting executable permissions."
}

function make_executable_and_run() {
  local script="$1"
  if [[ -z "$script" ]]; then
    echo "Usage: make_executable_and_run /path/to/script" >&2
    return 1
  fi
  if [[ ! -f "$script" ]]; then
    echo "Error: File not found: $script" >&2
    return 1
  fi
  chmod +x "$script" && "$script"
}

# =============================================================================
# DIRECTORIES
# =============================================================================

function directory_exists() {
  [[ -d "$1" ]]
}

function check_directory() {
  if ! directory_exists "$1"; then
    echo "Error: directory '$1' not found" >&2
    exit 1
  fi
}

# =============================================================================
# ENVIRONMENTS
# =============================================================================

function get_desktop_env() {
  if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
    case "$XDG_CURRENT_DESKTOP" in
    *KDE*)      echo "KDE"      ;;
    *Hyprland*) echo "Hyprland" ;;
    *)          echo "$XDG_CURRENT_DESKTOP" ;;
    esac
    return
  fi
  if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    if pgrep -x hyprland >/dev/null 2>&1; then
      echo "Hyprland"
    elif pgrep -x kwin_wayland >/dev/null 2>&1; then
      echo "KDE"
    else
      echo "Wayland"
    fi
    return
  fi
  if [[ -n "${DISPLAY:-}" ]]; then
    if pgrep -x kwin_x11 >/dev/null 2>&1; then
      echo "KDE"
    else
      echo "X11"
    fi
    return
  fi
  echo "Unknown"
}

function is_kde()      { [[ "$(get_desktop_env)" == "KDE" ]]; }
function is_hyprland() { [[ "$(get_desktop_env)" == "Hyprland" ]]; }

# =============================================================================
# PACKAGES
# =============================================================================

function package_installed() {
  pacman -Q "$1" &>/dev/null
}

# =============================================================================
# NOTIFICATIONS
# =============================================================================

function send_user_notification() {
  local title="$1"
  local message="$2"
  local icon="${3:-dialog-information}"
  local app_name="${4:-Notification}"
  local timeout="${5:-15000}"
  local desktop_entry="${6:-$app_name}"

  if [[ -z "${SUDO_USER:-}" ]]; then
    echo "This function must be run with sudo." >&2
    return 1
  fi

  local user_id dbus_address
  user_id="$(id -u "$SUDO_USER")"
  dbus_address="/run/user/${user_id}/bus"

  if [[ -S "$dbus_address" ]]; then
    if loginctl show-user "$SUDO_USER" | grep -q 'Display='; then
      sudo -u "$SUDO_USER" \
        DISPLAY=:0 \
        DBUS_SESSION_BUS_ADDRESS="unix:path=${dbus_address}" \
        notify-send -a "$app_name" \
        -h "string:desktop-entry:${desktop_entry}" \
        -t "$timeout" \
        -i "$icon" \
        "$title" \
        "$message"
    fi
  fi
}
