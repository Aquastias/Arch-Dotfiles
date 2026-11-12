#!/usr/bin/env bash
# =============================================================================
# lib/guided/controller-packages.sh — package-list edits on the Config State
# =============================================================================
# Part of the guided controller (lib/guided/controller.sh, ADR 0042): add,
# drop, exclude and un-exclude one package, as the package screens toggle it.
#
# Used by: lib/guided/controller-enter-users.sh.
# =============================================================================
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

# _controller_package_exclude <state> <package> — the state with <package>
# in packages.exclude (once).
_controller_package_exclude() {
  local exclude='.packages.exclude = (((.packages.exclude // []) + [$p])'
  exclude+=' | unique)'
  # The exclude list with the package added, sorted, no repeats.
  printf '%s\n' "$1" | jq --arg p "$2" "$exclude"
}

# _controller_package_unexclude <state> <package> — the state with <package>
# out of packages.exclude; an emptied list is dropped.
_controller_package_unexclude() {
  local state="$1" unexclude='if .packages.exclude'
  unexclude+=' then .packages.exclude |= map(select(. != $p)) else . end'
  # The exclude list without the package.
  state="$(printf '%s\n' "$state" | jq --arg p "$2" "$unexclude")"
  # An emptied exclude list is dropped.
  if printf '%s\n' "$state" | jq -e '.packages.exclude == []' >/dev/null; then
    state="$(printf '%s\n' "$state" | jq 'del(.packages.exclude)')"
  fi
  printf '%s\n' "$state"
}

# _controller_package_add <state> <slot> <category> <package> — the state with
# <package> in packages.<slot>.<category> (once).
_controller_package_add() {
  local add='.packages[$s][$k] = (((.packages[$s][$k] // []) + [$p])'
  add+=' | unique)'
  # The category list with the package added, sorted, no repeats.
  printf '%s\n' "$1" | jq --arg s "$2" --arg k "$3" --arg p "$4" "$add"
}

# _controller_package_drop <state> <slot> <category> <package> — the state
# with <package> out of packages.<slot>.<category>, when that list exists.
_controller_package_drop() {
  local drop='if .packages[$s][$k]'
  drop+=' then .packages[$s][$k] |= map(select(. != $p)) else . end'
  # The category list without the package.
  printf '%s\n' "$1" | jq --arg s "$2" --arg k "$3" --arg p "$4" "$drop"
}

# _controller_package_in_baseline_any <slot> <pkg> — rc 0 when <pkg> is in ANY
# of the session baseline's <slot> category arrays. The browser has no single
# pkgcat, so it tests the whole slot to decide add-vs-exclude the way
# _controller_enter_packages does per-cat.
_controller_package_in_baseline_any() {
  local in_slot='[(.packages[$s] // {}) | .[] | .[]?] | index($p)'
  # The package's position among the slot's packages (null when absent).
  _controller_baseline \
    | jq -e --arg s "$1" --arg p "$2" "$in_slot" >/dev/null 2>&1
}
