#!/usr/bin/env bash
# =============================================================================
# lib/guided-fzf-entry.sh — persistent-fzf bind entry point (ADR 0042)
# =============================================================================
# The command the single persistent fzf's binds invoke. fzf runs binds in fresh
# shells, so this sources the controller (+ guided helpers for one-shot) and
# dispatches:
#   list                    → the current screen's item list (for `reload`)
#   dispatch <verb> <line>  → run the controller, print the fzf action string
#                             that the `transform` bind then executes
#   oneshot <field>         → run the existing one-shot edit helper for <field>
#
# State lives in the GUIDED_*_FILE paths the launcher exported. This is the live
# glue: it is UNVERIFIED by bats (it needs a tty + fzf) and is exercised at the
# slice-01 VM / HITL gate. The dispatch LOGIC it calls (the controller + the
# directive→action translation) is unit-tested in tests/config/guided-*.bats.
# =============================================================================
set -uo pipefail

_entry_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_entry_self="${_entry_dir}/guided-fzf-entry.sh"
export OS_DIR="${OS_DIR:-$(cd "${_entry_dir}/.." && pwd)}"

# shellcheck source=lib/guided-controller.sh
source "${_entry_dir}/guided-controller.sh"

case "${1:-}" in
list)
  guided_ctl_list
  ;;
dispatch)
  _verb="${2:-}"; _line="${3:-}"; _d="noop"
  case "$_verb" in
  enter) _d="$(guided_ctl_enter "$_line")" ;;
  back)  _d="$(guided_ctl_back)" ;;
  esac
  _guided_directive_to_action "$_d" "$_entry_self"
  ;;
oneshot)
  # shellcheck source=lib/guided.sh
  source "${_entry_dir}/guided.sh"
  _guided_oneshot_edit "${2:-}"
  ;;
esac
