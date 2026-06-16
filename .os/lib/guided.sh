#!/usr/bin/env bash
# =============================================================================
# lib/guided.sh — Guided Installer fzf shell (ADR 0039)
# =============================================================================
# The only impure module of the Guided Installer: it renders menus, reads the
# operator's choices, and dispatches to the pure cores (Config State, Emitter,
# Menu model). It holds no decision logic — every value flows through the pure
# layer, and the assembled Effective Config is the same artifact the back-end
# and VM suite already cover.
#
# Selection seam — the shell selects ONLY through these:
#   guided_prompt <key> <prompt>            free-text (read, or replay)
#   guided_select <key> <prompt> <opt...>   enumerable pick (fzf, or replay)
#   guided_pick_disk [<key>]                disk pick w/ picker preview, or
#                                           replay
# Interactively they render fzf / a typed prompt; under a replay answers file
# (guided_load_replay, set by `install.sh --guided <file>`) each returns the
# scripted answer by key — no fzf, no tty. This is the seam a headless harness
# (issue 01b) drives.
#
# guided_build → the device-baked Effective Config on stdout. The review screen
# + typed INSTALL are the single consent gate; the caller (install.sh) runs the
# back-end `--unattended`.
# =============================================================================

# shellcheck source=lib/common.sh
[[ "$(type -t error)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/common.sh"
# shellcheck source=lib/config/state.sh
[[ "$(type -t cfgstate_new)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/config/state.sh"
# shellcheck source=lib/config/emit.sh
[[ "$(type -t emit_effective)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/config/emit.sh"
# shellcheck source=lib/config/menu.sh
[[ "$(type -t menu_rows)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/config/menu.sh"
# shellcheck source=lib/picker.sh
[[ "$(type -t picker_enum_disks)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/picker.sh"
# shellcheck source=lib/live-medium.sh
[[ "$(type -t live_medium_disks)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/live-medium.sh"

# =============================================================================
# SELECTION SEAM
# =============================================================================

declare -gA _GUIDED_ANSWERS=()
_GUIDED_REPLAY=0

# guided_load_replay <file> — load a key=value answers file (one per line) for
# headless replay. Subsequent seam calls return the scripted answer by key.
guided_load_replay() {
  local file="$1" line k v
  declare -gA _GUIDED_ANSWERS=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == *=* ]] || continue
    k="${line%%=*}"
    v="${line#*=}"
    _GUIDED_ANSWERS["$k"]="$v"
  done <"$file"
  _GUIDED_REPLAY=1
}

# guided_prompt <key> <prompt> — a typed free-text value.
guided_prompt() {
  local key="$1" prompt="$2" v
  if ((_GUIDED_REPLAY)); then
    printf '%s' "${_GUIDED_ANSWERS[$key]-}"
    return
  fi
  read -rp "  ${prompt}: " v </dev/tty
  printf '%s' "$v"
}

# guided_select <key> <prompt> <option...> — pick one of the enumerated values.
guided_select() {
  local key="$1" prompt="$2"
  shift 2
  if ((_GUIDED_REPLAY)); then
    printf '%s' "${_GUIDED_ANSWERS[$key]-}"
    return
  fi
  printf '%s\n' "$@" | fzf --reverse --prompt="${prompt}> "
}

# guided_pick_disk [<key>] — resolve one disk via the Pre-Install Picker
# (lsblk/SMART preview), or the scripted answer under replay.
guided_pick_disk() {
  local key="${1:-disk}" live
  if ((_GUIDED_REPLAY)); then
    printf '%s' "${_GUIDED_ANSWERS[$key]-}"
    return
  fi
  live="$(live_medium_disks)"
  local -a cands
  mapfile -t cands < <(picker_enum_disks "$live")
  ((${#cands[@]})) || { error "guided: no /dev/disk/by-id/* candidates found"; \
    return 1; }
  printf '%s\n' "${cands[@]}" | fzf --reverse --prompt='disk> ' \
    --preview="bash -c 'source \"${OS_DIR}/lib/picker.sh\"; \
      picker_format_disk_preview {}'" \
    --preview-window=right,60%
}

# =============================================================================
# ASSEMBLY
# =============================================================================
# In-flight session state for one guided run — the Config State plus the picked
# disk. Mutated by the edit helpers, which are shared by the interactive menu
# and the headless replay path so both exercise the same Config-State writes.
_GUIDED_STATE=""
_GUIDED_DISK=""

# _guided_set_identity — seed the required identity defaults + the single-disk
# ZFS preset. validation.sh requires system.locale + system.timezone; issue 05
# turns locale/timezone/keymap into live-system-picked rows over these.
_guided_set_identity() {
  _GUIDED_STATE="$(cfgstate_set "$_GUIDED_STATE" system.locale '"en_US.UTF-8"')"
  _GUIDED_STATE="$(cfgstate_set "$_GUIDED_STATE" system.timezone '"UTC"')"
  _GUIDED_STATE="$(cfgstate_set "$_GUIDED_STATE" system.keymap '"us"')"
  _GUIDED_STATE="$(cfgstate_set "$_GUIDED_STATE" mode '"single"')"
}

# _guided_edit_hostname — read the hostname (seam key 'hostname') and commit it.
_guided_edit_hostname() {
  local v
  v="$(guided_prompt hostname "Hostname")"
  [[ -n "$v" ]] && _GUIDED_STATE="$(cfgstate_set "$_GUIDED_STATE" \
    system.hostname "$(jq -n --arg x "$v" '$x')")"
}

# _guided_edit_disk — resolve the single install disk (Disks ▸ ZFS ▸ single).
_guided_edit_disk() { _GUIDED_DISK="$(guided_pick_disk disk)"; }

# _guided_menu_lines <state> — the menu's display lines: one per menu row
# (Section · label: value, ● when overridden). Pure: menu_rows JSON → lines.
_guided_menu_lines() {
  menu_rows "$1" | jq -r '
    .[] | "\(.section) · \(.label): \(.value // "")"
          + (if .overridden then "  ●" else "" end)'
}

# _guided_menu_loop — the re-entrant Host / Users split menu (interactive only,
# fzf, smoke-only). Renders the rows, lets the operator edit the hostname and
# pick the install disk, and returns 0 on Proceed (a disk is picked), non-zero
# on cancel (Esc). Edits commit to the Config State, so leaving and re-entering
# never loses a value.
_guided_menu_loop() {
  local choice
  local -a lines
  while true; do
    mapfile -t lines < <(_guided_menu_lines "$_GUIDED_STATE")
    lines+=("Disks · install disk: ${_GUIDED_DISK:-(none — pick one)}")
    lines+=("Proceed ▸ review & install")
    choice="$(printf '%s\n' "${lines[@]}" \
      | fzf --reverse --prompt='guided> ')" || return 1
    case "$choice" in
    *hostname*) _guided_edit_hostname ;;
    Disks* | *filesystem*) _guided_edit_disk ;;
    Proceed*)
      [[ -n "$_GUIDED_DISK" ]] && return 0
      printf '  Pick an install disk first.\n' >&2
      ;;
    *) : ;; # Users + non-editable rows: no-op in the tracer (issue 07)
    esac
  done
}

# guided_build — drive the guided menu and emit the device-baked Effective
# Config on stdout. Interactive: the re-entrant Host / Users split menu.
# Headless (--guided replay): a linear keyed collection through the SAME edit
# helpers. The typed INSTALL is the sole consent gate; non-zero (no output) if
# it is withheld.
guided_build() {
  local assignment effective confirm hostname
  _GUIDED_STATE="$(cfgstate_new)"
  _GUIDED_DISK=""
  _guided_set_identity

  if ((_GUIDED_REPLAY)); then
    _guided_edit_hostname
    _guided_edit_disk
  else
    _guided_menu_loop || { error "guided: cancelled"; return 1; }
  fi

  [[ -n "$_GUIDED_DISK" ]] || { error "guided: no disk selected"; return 1; }
  assignment="$(jq -n --arg d "$_GUIDED_DISK" '{mode:"single", disk:$d}')"
  effective="$(emit_effective "$_GUIDED_STATE" "$assignment")" || return 1

  # Review + the single consent gate. Human-facing → stderr; stdout carries only
  # the Effective Config the caller captures.
  hostname="$(cfgstate_get "$_GUIDED_STATE" system.hostname)"
  section "Review" >&2
  printf '  Host:        %s\n' "${hostname:-(prompted at install)}" >&2
  printf '  WILL ERASE:  %s\n' "$_GUIDED_DISK" >&2
  confirm="$(guided_prompt confirm "Type INSTALL to continue")"
  [[ "$confirm" == "INSTALL" ]] \
    || { error "guided: aborted — INSTALL not typed"; return 1; }

  printf '%s\n' "$effective"
}
