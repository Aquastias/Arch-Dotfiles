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

# guided_build — drive the (single-disk ZFS) menu and emit the device-baked
# Effective Config on stdout. The typed INSTALL is the sole consent gate;
# returns non-zero (no output) if it is not given.
guided_build() {
  local state hostname disk confirm assignment effective
  state="$(cfgstate_new)"

  hostname="$(guided_prompt hostname "Hostname")"
  [[ -n "$hostname" ]] && state="$(cfgstate_set "$state" system.hostname \
    "$(jq -n --arg v "$hostname" '$v')")"

  # Single-disk ZFS preset — the filesystem axis is reserved (zfs only) here.
  state="$(cfgstate_set "$state" mode '"single"')"
  disk="$(guided_pick_disk disk)"
  [[ -n "$disk" ]] || { error "guided: no disk selected"; return 1; }

  assignment="$(jq -n --arg d "$disk" '{mode:"single", disk:$d}')"
  effective="$(emit_effective "$state" "$assignment")" || return 1

  # Review + the single consent gate.
  section "Review"
  printf '  Host:        %s\n' "${hostname:-(prompted at install)}" >&2
  printf '  WILL ERASE:  %s\n' "$disk" >&2
  confirm="$(guided_prompt confirm "Type INSTALL to continue")"
  [[ "$confirm" == "INSTALL" ]] \
    || { error "guided: aborted — INSTALL not typed"; return 1; }

  printf '%s\n' "$effective"
}
