#!/usr/bin/env bash
# lib/chroot/extras-common.sh — shared helpers for DE extras adapters
# Callers set DE_TAG before sourcing (e.g. DE_TAG=KDE).

_EC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_EC_COMMON="${_EC_DIR}/../common.sh"
if [[ -f "$_EC_COMMON" ]]; then
  # shellcheck source=/dev/null
  source "$_EC_COMMON"
else
  jsonc() { sed -e 's|[[:space:]]*//[^"]*$||' -e '/^[[:space:]]*\/\//d' "$1"; }
  GREEN='' CYAN='' BOLD='' NC=''
fi
unset _EC_DIR _EC_COMMON

info()    { echo -e "${GREEN}[${DE_TAG:-DE}]${NC}  $*"; }
section() { echo -e "\n${CYAN}${BOLD}━━━  $*  ━━━${NC}"; }
