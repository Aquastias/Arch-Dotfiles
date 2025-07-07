#!/usr/bin/env bash

# Return true (0) if the first string (haystack) contains the second string (needle), and false (1) otherwise.
function string_contains() {
  local -r haystack="$1"
  local -r needle="$2"

  [[ "$haystack" == *"$needle"* ]]
}

# Returns true (0) if the first string (haystack), which is assumed to contain multiple lines, contains the second
# string (needle), and false (1) otherwise. The needle can contain regular expressions.
function string_multiline_contains() {
  local -r haystack="$1"
  local -r needle="$2"

  echo "$haystack" | grep -q "$needle"
}

# Convert the given string to uppercase
function string_to_uppercase() {
  local -r str="$1"
  echo "$str" | awk '{print toupper($0)}'
}

# Strip the prefix from the given string. Supports wildcards.
#
# Example:
#
# string_strip_prefix "foo=bar" "foo="  ===> "bar"
# string_strip_prefix "foo=bar" "*="    ===> "bar"
#
# http://stackoverflow.com/a/16623897/483528
function string_strip_prefix() {
  local -r str="$1"
  local -r prefix="$2"
  echo "${str#$prefix}"
}

# Strip the suffix from the given string. Supports wildcards.
#
# Example:
#
# string_strip_suffix "foo=bar" "=bar"  ===> "foo"
# string_strip_suffix "foo=bar" "=*"    ===> "foo"
#
# http://stackoverflow.com/a/16623897/483528
function string_strip_suffix() {
  local -r str="$1"
  local -r suffix="$2"
  echo "${str%$suffix}"
}

# Return true if the given response is empty or "null" (the latter is from jq parsing).
function string_is_empty_or_null() {
  local -r response="$1"
  [[ -z "$response" || "$response" == "null" ]]
}

# Given a string $str, return the substring beginning at index $start and ending at index $end.
#
# Example:
#
# string_substr "hello world" 0 5 returns "hello"
function string_substr() {
  local -r str="$1"
  local -r start="$2"
  local end="$3"

  if [[ "$start" -lt 0 || "$end" -lt 0 ]]; then
    log_error "In the string_substr bash function, each of \$start and \$end must be >= 0."
    exit 1
  fi

  if [[ "$start" -gt "$end" ]]; then
    log_error "In the string_substr bash function, \$start must be < \$end."
    exit 1
  fi

  if [[ -z "$end" ]]; then
    end="${#str}"
  fi

  echo "${str:$start:$end}"
}

# Prints a message in a specified color
#
# Usage:
#
# print_status "This is a plain message."
# print_status success "Installation completed successfully."
# print_status error "Installation failed!"
# print_status warning "Low disk space."
# print_status info "Starting installation..."
# print_status custom red "This is a custom red message without prefix."
# print_status custom magenta "Custom magenta text."
# print_status custom unknown "No color because unknown color name."
function print_status() {
  local type="$1"
  shift

  local message
  local color_name

  # If no type provided, just print message plainly
  if [ -z "$type" ]; then
    message="$*"
    echo "$message"
    return
  fi

  # If type is "custom", next argument is color, then message
  if [ "$type" == "custom" ]; then
    color_name="$1"
    shift
    message="$*"
  else
    message="$*"
  fi

  # Define color codes
  local RED='\033[0;31m'
  local GREEN='\033[0;32m'
  local YELLOW='\033[0;33m'
  local BLUE='\033[0;34m'
  local MAGENTA='\033[0;35m'
  local CYAN='\033[0;36m'
  local WHITE='\033[0;37m'
  local NC='\033[0m' # No Color

  local color_code=""
  local prefix=""

  case "$type" in
  success)
    color_code="$GREEN"
    prefix="[SUCCESS]"
    ;;
  warning)
    color_code="$YELLOW"
    prefix="[WARNING]"
    ;;
  error)
    color_code="$RED"
    prefix="[ERROR]"
    ;;
  info)
    color_code="$BLUE"
    prefix="[INFO]"
    ;;
  custom)
    case "$color_name" in
    red) color_code="$RED" ;;
    green) color_code="$GREEN" ;;
    yellow) color_code="$YELLOW" ;;
    blue) color_code="$BLUE" ;;
    magenta) color_code="$MAGENTA" ;;
    cyan) color_code="$CYAN" ;;
    white) color_code="$WHITE" ;;
    *) color_code="$NC" ;; # default no color
    esac
    prefix="" # no prefix for custom
    ;;
  *)
    color_code="$NC"
    prefix=""
    ;;
  esac

  echo -e "${color_code}${prefix:+$prefix }$message${NC}"
}
