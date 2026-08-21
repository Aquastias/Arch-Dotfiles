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
  guided_ctl_list; echo   # trailing inert spacer → gap above the footer toolbar
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
oneshot)
  # shellcheck source=lib/guided.sh
  source "${_entry_dir}/guided.sh"
  _guided_oneshot_edit "${2:-}"
  ;;
cfdisk)
  # Manual Partitioning (ADR 0073): runs under fzf execute() (has a tty). Launch
  # cfdisk on the target disk, then scan the resulting table + store the
  # assignment into the guided state. The controller (sourced above) already
  # pulled in manual-partition.sh + picker.sh. VM/HITL-verified glue.
  _mdisk="$(manual_target_disk)" || exit 0
  _mcur="$(cat "$GUIDED_STATE_FILE")"
  if _mnew="$(manual_partition_flow "$_mcur" "$_mdisk")"; then
    printf '%s\n' "$_mnew" > "$GUIDED_STATE_FILE"
  fi
  ;;
pkgbrowse)
  # repo ＋Add (ADR 0086): the archinstall-style package browser, done in fzf.
  # Runs under fzf execute() (has a tty). Lists every repo package (pacman -Slq)
  # with a `pacman -Si` preview + multi-select, then routes each pick via the
  # ＋Add guard (_ctl_route_package_entry). Needs a synced pacman DB — an empty
  # list means `pacman -Sy` was never run (upstream archinstall issue #3307).
  # UNVERIFIED by bats (tty + live pacman DB); the routing it calls is tested.
  _pslot="${2:-repo}"
  if ! command -v pacman >/dev/null 2>&1; then
    printf 'pacman is not available — cannot browse packages.\n' >&2
    sleep 2 || true; exit 0
  fi
  _plist="$(pacman -Slq 2>/dev/null)"
  if [[ -z "$_plist" ]]; then
    printf 'No repo packages listed — run `pacman -Sy` first, then retry.\n' >&2
    sleep 2 || true; exit 0
  fi
  _picks="$(printf '%s\n' "$_plist" | fzf --multi --reverse \
    --prompt="${_pslot} package (TAB to mark)> " \
    --preview 'pacman -Si {} 2>/dev/null' --preview-window=right,60% \
    | tr '\n' ' ')"
  [[ -n "${_picks// /}" ]] || exit 0
  _pcur="$(cat "$GUIDED_STATE_FILE")"
  if _pnew="$(_ctl_route_package_entry "$_pcur" "$_picks" "$_pslot")"; then
    printf '%s\n' "$_pnew" > "$GUIDED_STATE_FILE"
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
