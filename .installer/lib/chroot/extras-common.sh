#!/usr/bin/env bash
# lib/chroot/extras-common.sh — shared helpers for DE extras adapters
# Callers set DE_TAG before sourcing (e.g. DE_TAG=KDE).

_EC_DIR="${BASH_SOURCE[0]%/*}"
[[ "$_EC_DIR" != "${BASH_SOURCE[0]}" ]] || _EC_DIR=.
_EC_DIR="$(cd "$_EC_DIR" && pwd)"
_EC_COMMON="${_EC_DIR}/../common.sh"
if [[ -f "$_EC_COMMON" ]]; then
  # shellcheck source=/dev/null
  source "$_EC_COMMON"
else
  # Without the stdlib, strip comments with the same program jsonc.sh
  # uses (staged beside common.sh).
  _EC_JSONC_STRIP="${_EC_DIR}/../jsonc-strip.awk"
  jsonc() { awk -f "$_EC_JSONC_STRIP" "$1"; }
  GREEN='' CYAN='' BOLD='' NC=''
fi
unset _EC_DIR _EC_COMMON

info()    { echo -e "${GREEN}[${DE_TAG:-DE}]${NC}  $*"; }
section() { echo -e "\n${CYAN}${BOLD}━━━  $*  ━━━${NC}"; }

# ── Line edits of config files (ADR 0167: these replace sed's address forms)
# Each keeps the file's owner and mode. (The `|| -n` keeps a last line that
# has no newline.)

# append_after_matching <file> <extended-regex> <line> — put <line> right
# after every line of <file> that matches.
append_after_matching() {
  local file="$1" pattern="$2" added="$3" edited line
  edited="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "$line"
    if printf '%s\n' "$line" | grep -qE "$pattern"; then
      printf '%s\n' "$added"
    fi
  done < "$file" > "$edited"
  cat "$edited" > "$file"
  rm -f "$edited"
}

# remove_block <file> <begin-regex> <end-regex> — delete each block of <file>
# from a line matching <begin-regex> through the next line matching
# <end-regex> (both included).
remove_block() {
  local file="$1" begin="$2" end="$3" edited line in_block=0
  edited="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if (( in_block )); then
      printf '%s\n' "$line" | grep -qE "$end" && in_block=0
      continue
    fi
    if printf '%s\n' "$line" | grep -qE "$begin"; then
      in_block=1
      continue
    fi
    printf '%s\n' "$line"
  done < "$file" > "$edited"
  cat "$edited" > "$file"
  rm -f "$edited"
}
