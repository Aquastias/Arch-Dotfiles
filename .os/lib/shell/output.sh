#!/usr/bin/env bash
# lib/shell/output.sh — status printing helpers

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
