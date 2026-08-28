#!/usr/bin/env bash
# =============================================================================
# lib/guided-fzf-entry.sh — persistent-fzf bind entry point (ADR 0042)
# =============================================================================
# The command the single persistent fzf's binds invoke. fzf runs binds in fresh
# shells, so this sources the controller and dispatches:
#   list                    → the current screen's item list (for `reload`)
#   dispatch <verb> <line>  → run the controller, print the fzf action string
#                             that the `transform` bind then executes
#   cfdisk / secret         → tty-hosted execute() hand-offs
#
# State lives in the GUIDED_*_FILE paths the launcher exported. This is the live
# glue: it is UNVERIFIED by bats (it needs a tty + fzf) and is exercised at the
# slice-01 VM / HITL gate. The dispatch LOGIC it calls (the controller + the
# directive→action translation) is unit-tested in tests/config/guided-*.bats.
# =============================================================================
set -uo pipefail

_entry_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_entry_self="${_entry_dir}/guided-fzf-entry.sh"
export INSTALLER_DIR="${INSTALLER_DIR:-$(cd "${_entry_dir}/.." && pwd)}"

# The focus skip bind fires on every cursor move; source only the tiny row
# classifier (not the whole controller) so it stays cheap. On an inert row it
# echoes the last movement direction (up/down, recorded by the up/down binds)
# so fzf re-moves and the cursor hops past dividers / headers / spacers (ADR
# 0083). On a selectable row it echoes nothing, so the cursor settles.
if [[ "${1:-}" == "skip" ]]; then
  # shellcheck source=lib/guided-rows.sh
  source "${_entry_dir}/guided-rows.sh"
  if guided_row_inert "${2:-}"; then
    cat "${GUIDED_SKIP_FILE:-/dev/null}" 2>/dev/null
  fi
  exit 0
fi

# The `load` bind fires after every (re)load. A back nav stashes the 1-based line
# to re-focus in GUIDED_POS_FILE (as a side effect of building its reload action,
# so the write lands before load); emit the deferred `pos` and consume it, so the
# cursor lands on the exited row instead of the reload's stale index (ADR 0083).
# A `pos` inside the reload's own action string would target the PRE-reload list.
# One-shot: cleared on read so an ordinary reload (enter/refresh) never re-jumps.
if [[ "${1:-}" == "poshint" ]]; then
  _pf="${GUIDED_POS_FILE:-}"
  if [[ -n "$_pf" ]]; then
    _pn="$(cat "$_pf" 2>/dev/null)"
    if [[ -n "$_pn" ]]; then : >"$_pf"; printf 'pos(%s)' "$_pn"; fi
  fi
  exit 0
fi

# The masking bind fires per keystroke on the password screen; source only the
# tiny pure core (not the whole controller) so it stays cheap.
if [[ "${1:-}" == "mask" ]]; then
  # shellcheck source=lib/guided-mask.sh
  source "${_entry_dir}/guided-mask.sh"
  _q="${2:-}"
  _buf="$(cat "${GUIDED_PWBUF_FILE:-/dev/null}" 2>/dev/null)"
  _res="$(guided_mask_apply "$_buf" "$_q")"
  printf '%s' "${_res%%$'\n'*}" > "${GUIDED_PWBUF_FILE:-/dev/null}"
  printf '%s' "${_res##*$'\n'}"     # the bullet display → transform-query sets it
  exit 0
fi

# shellcheck source=lib/guided-controller.sh
source "${_entry_dir}/guided-controller.sh"

case "${1:-}" in
list)
  guided_ctl_list
  ;;
dispatch)
  _verb="${2:-}"; _line="${3:-}"; _query="${4:-}"; _d="noop"
  case "$_verb" in
  enter) _d="$(guided_ctl_enter "$_line" "$_query")" ;;
  back)  _d="$(guided_ctl_back)" ;;
  esac
  _guided_directive_to_action "$_d" "$_entry_self"
  ;;
key)
  # ^A add / ^S add storage / ^X remove — context actions (rich chrome); ^Z/^Y/^R
  # — undo/redo/reset. ^X carries the highlighted line ({}) so it can remove the
  # pool under the cursor on the datapools list.
  case "${2:-}" in
  ctrl-a) _dk="$(guided_ctl_action add)" ;;
  ctrl-s) _dk="$(guided_ctl_action add-storage)" ;;
  ctrl-x) _dk="$(guided_ctl_action remove "${3:-}")" ;;
  *)      _dk="$(guided_ctl_key "${2:-}")" ;;
  esac
  _guided_directive_to_action "$_dk" "$_entry_self"
  ;;
preview)
  # fzf preview body — the ASCII layout graph (only on the Disk-layout screen).
  guided_ctl_preview "${2:-}"
  ;;
cfdisk)
  # Manual Partitioning (ADR 0073): runs under fzf execute() (has a tty). Launch
  # cfdisk on the target disk, then scan the resulting table + store the
  # assignment into the guided state. The controller (sourced above) already
  # pulled in manual-partition.sh + picker.sh. VM/HITL-verified glue.
  _mdisk="$(manual_target_disk)" || exit 0
  _mcur="$(cfgstore_state)"
  if _mnew="$(manual_partition_flow "$_mcur" "$_mdisk")"; then
    cfgstore_write_state "$_mnew"
  fi
  ;;
secret)
  # In-menu credential capture (ticket 03): a masked, confirmed prompt on the
  # tty, written to the handoff file. Runs under fzf execute() (has a tty).
  # shellcheck source=lib/prompt.sh
  source "${_entry_dir}/prompt.sh"
  # shellcheck source=lib/guided-secrets-file.sh
  source "${_entry_dir}/guided-secrets-file.sh"
  _spw=""
  case "${2:-}" in
  root) prompt_secret _spw "Root password"
        guided_secretsfile_set_root "${GUIDED_SECRETS_FILE}" "$_spw" ;;
  user) prompt_secret _spw "Password for ${3:-user}"
        guided_secretsfile_set_user \
          "${GUIDED_SECRETS_FILE}" "${3:-user}" "$_spw" ;;
  enc)  prompt_secret _spw "Encryption password" 8
        guided_secretsfile_set_enc "${GUIDED_SECRETS_FILE}" "$_spw" ;;
  esac
  ;;
esac
