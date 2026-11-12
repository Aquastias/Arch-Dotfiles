#!/usr/bin/env bash
# =============================================================================
# lib/guided/controller-lists.sh — small JSON-array and name-list helpers
# =============================================================================
# Part of the guided controller (lib/guided/controller.sh, ADR 0042): append,
# flip and test one value in a JSON array; drop the Menu-Owned Programs from a
# name list.
#
# Used by: lib/guided/controller-fields.sh.
# =============================================================================
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

# _controller_json_with <array-json> <value> — the array with <value> appended
# unless it is already there.
_controller_json_with() {
  # The array, the value appended when absent.
  printf '%s\n' "$1" \
    | jq -c --arg v "$2" 'if index($v) then . else . + [$v] end'
}

# _controller_json_toggled <array-json> <value> — the array with <value>
# removed when present, appended when not.
_controller_json_toggled() {
  local toggled='if index($v) then . - [$v] else . + [$v] end'
  # The array, the value flipped in or out.
  printf '%s\n' "$1" \
    | jq -c --arg v "$2" "$toggled"
}

# _controller_json_has <array-json> <value> — rc 0 when the array holds
# <value>.
_controller_json_has() {
  # The value's position (null when absent).
  printf '%s\n' "$1" | jq -e --arg v "$2" 'index($v)' >/dev/null
}

# _controller_without_menu_owned — stdin's names minus the [[Menu-Owned
# Program]]s, in order.
_controller_without_menu_owned() {
  local -A owned=()
  local name
  while IFS= read -r name; do
    [[ -n "$name" ]] && owned["$name"]=1
  done < <(menu_owned_programs)
  while IFS= read -r name; do
    [[ -n "${owned["$name"]:-}" ]] || printf '%s\n' "$name"
  done
}

# _controller_selected_values <field> <effective> — the field's value as a
# JSON array: [] when unset, a lone value wrapped.
_controller_selected_values() {
  local as_array='. // [] | if type == "array" then . else [.] end'
  # The value, as an array.
  config_state_get_json "$2" "$1" | jq -c "$as_array"
}
