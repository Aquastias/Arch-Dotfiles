#!/usr/bin/env bash
# =============================================================================
# lib/guided/controller-enter-host.sh — enter dispatch: top, profiles, host, category
# =============================================================================
# Part of the guided controller (lib/guided/controller.sh, ADR 0042).
#
# Used by: lib/guided/controller.sh (sources it).
# =============================================================================

_controller_enter_top() {
  local line="$1" cat
  case "$line" in
  "$_CONTROLLER_DIVIDER")  echo noop ;;
  "Profiles ▸"*)    _controller_write_navigation "$(navigation_to_profiles)"; echo render ;;
  "Proceed"*)       _controller_proceed_directive ;;
  "Save profile"*)  echo "terminal save" ;;
  "Export config"*) echo "terminal export" ;;
  "Abort"*)         echo abort ;;
  *)
    # The top row is "<name> — <summary>"; split on the em-dash so multi-word
    # category names (e.g. "Mirrors & Repositories") survive whole (ADR 0071).
    # Validity is read from menu_categories (the single source of truth), so a
    # new category needs no edit here.
    cat="${line%% — *}"
    if [[ "$cat" == "Users" ]]; then
      # Flatten (slice 01): Users opens its list directly, skipping the
      # single-row category screen. navigation_back from here returns to top.
      _controller_write_navigation "$(navigation_to_values Users users users)"; echo render
    elif menu_categories "$(_controller_state)" "$(_controller_baseline)" \
         | jq -e --arg c "$cat" 'any(.[]; .name == $c)' >/dev/null 2>&1; then
      _controller_write_navigation "$(navigation_to_category "$cat")"; echo render
    else
      echo noop
    fi ;;
  esac
}

# _controller_enter_profiles <line> — Enter on the Profiles screen (ADR 0055). `← Back`
# returns to the top screen unchanged. A profile row SEEDS the menu: the chosen
# hosts/<name>/profile.jsonc is parsed and merged over the current Config State
# (profiles_seed — profile wins, devices flattened), so every category reflects
# it, then nav returns to the top screen for tweak-or-Proceed. A profile that
# fails to parse leaves the state untouched and warns via a notice.
_controller_enter_profiles() {
  local line="$1" nav f profile
  nav="$(_controller_navigation)"
  if [[ "$line" == "← Back" ]]; then
    _controller_write_navigation "$(navigation_back "$nav")"; echo render; return
  fi
  # `↺ Reset to blank` (ADR 0063): a full session reset is destructive,
  # so drill into a confirm screen rather than resetting on the spot.
  if [[ "$line" == "↺ Reset to blank"* ]]; then
    _controller_write_navigation "$(navigation_to_new_host)"; echo render; return
  fi
  f="$(_controller_hosts_root)/${line}/profile.jsonc"
  if ! profile="$(_program_registry_parse "$f" 2>/dev/null)"; then
    echo "notice ⚠ Could not read profile '${line}'"; return
  fi
  # Seed the RESOLVED profile, not the raw delta. A committed profile is a
  # delta over Host Core, and the Config State is an override map that
  # REPLACES baseline values — so seeding the delta verbatim would show (and
  # install) `host_programs: ["grub"]` where `install.sh --profile desktop`
  # installs `["cups","grub"]`. Resolving here means one profile produces one
  # install through every front-end.
  profile="$(layer_resolver_resolve host "$(config_state_host_core)" "$profile")"
  _controller_write_state "$(profiles_seed "$(_controller_state)" "$profile")"
  _controller_write_navigation '{"screen":"top"}'
  echo render
}

# _controller_session_stash — snapshot the pre-reset session side-state (per-user
# editor forms + the password/secret manifest) into GUIDED_SESSION_UNDO_FILE, so
# a single undo after a `+ New host` reset can restore it. The Config State is
# already undoable through the history stack; this covers only the two side
# files the stack does not. No-op when no undo file is wired (non-persistent).
_controller_session_stash() {
  [[ -n "${GUIDED_SESSION_UNDO_FILE:-}" ]] || return 0
  local uf='{}' sf='{}'
  [[ -s "${GUIDED_USERFORMS_FILE:-}" ]] && uf="$(<"$GUIDED_USERFORMS_FILE")"
  [[ -s "${GUIDED_SECRETS_FILE:-}" ]] && sf="$(<"$GUIDED_SECRETS_FILE")"
  jq -n --argjson u "$uf" --argjson s "$sf" '{userforms:$u, secrets:$s}' \
    >"$GUIDED_SESSION_UNDO_FILE"
}

# _controller_session_unstash — restore the userforms + secrets files from the stash
# and drop it. Called by the first undo after a `+ New host` reset. No-op when
# the stash is absent/empty (nothing to restore).
_controller_session_unstash() {
  [[ -s "${GUIDED_SESSION_UNDO_FILE:-/nonexistent}" ]] || return 0
  local b; b="$(<"$GUIDED_SESSION_UNDO_FILE")"
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] \
    && jq -c '.userforms // {}' <<<"$b" >"$GUIDED_USERFORMS_FILE"
  [[ -n "${GUIDED_SECRETS_FILE:-}" ]] \
    && jq -c '.secrets // {}' <<<"$b" >"$GUIDED_SECRETS_FILE"
  rm -f "$GUIDED_SESSION_UNDO_FILE"
}

# _controller_new_host_reset — the `+ New host` full session reset (ADR 0063). Broader
# than Reset-all (which clears Config State only): it returns Config State to
# the Host Core baseline (a `{}` override map — like ^R, and recorded on the
# undo stack) AND clears the session-created users' editor forms and the secret
# / password manifest overrides (the in-menu disk bindings live in Config State,
# so the `{}` reset drops them too). The side files are stashed first, so a
# single undo restores the whole pre-reset session.
_controller_new_host_reset() {
  _controller_session_stash
  if [[ -f "${GUIDED_HIST_FILE:-/nonexistent}" ]]; then
    local hist; hist="$(<"$GUIDED_HIST_FILE")"
    hist="$(history_commit "$hist" '{}')"
    printf '%s\n' "$hist" >"$GUIDED_HIST_FILE"
    _controller_write_state "$(history_present "$hist")"
  else
    _controller_write_state '{}'
  fi
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] \
    && printf '{}\n' >"$GUIDED_USERFORMS_FILE"
  [[ -n "${GUIDED_SECRETS_FILE:-}" ]] && printf '{}\n' >"$GUIDED_SECRETS_FILE"
}

# _controller_enter_new_host <line> — the `+ New host` confirm screen (ADR 0063): the
# confirm row runs the full session reset and returns to a blank top screen; any
# other row (← Back) cancels back to the picker, session work intact.
# _controller_manual_set <state> <device> <field> <value> → state with one field of the
# partition <device> changed (via the pure manual_partition_set_field),
# re-stored under disk_config.partitions. The single write path the assignment
# editor uses.
_controller_manual_set() {
  local st="$1" dev="$2" field="$3" val="$4" parts
  parts="$(config_state_get "$st" disk_config.partitions)"
  manual_partition_store "$st" \
    "$(manual_partition_set_field "${parts:-[]}" "$dev" "$field" "$val")"
}

# _controller_manual_field <state> <device> <field> → the current value of <field> on
# the partition <device> (empty when unset).
_controller_manual_field() {
  jq -r --arg d "$2" --arg f "$3" '
    (.disk_config.partitions // [])[]
    | select(.device == $d) | (.[$f] // "")
  ' <<< "$1"
}

# _controller_enter_manual_partitions <line> — the assignment table: the cfdisk hand-off
# action, then one row per partition (opens its editor). cfdisk is gated in
# --debug (ADR 0063: inspect-only, no disk touched).
_controller_enter_manual_partitions() {
  local line="$1" nav cat; nav="$(_controller_navigation)"; cat="$(navigation_get "$nav" category)"
  case "$line" in
  "← Back") _controller_write_navigation "$(navigation_back "$nav")"; echo render; return ;;
  "⟳ Run cfdisk"*)
    [[ "${INSTALL_DEBUG:-0}" == "1" ]] \
      && { echo 'notice cfdisk is disabled in --debug — no disk is touched'
           return; }
    echo cfdisk; return ;;
  "/dev/"*)
    local dev="${line%%  *}"
    _controller_write_navigation "$(navigation_to_partition_edit "$cat" "$dev")"; echo render; return ;;
  *) echo noop ;;
  esac
}

# _controller_enter_partition_edit <line> — the per-partition editor: Enter cycles the
# mountpoint / filesystem, or toggles format. Only supported filesystems and
# mountpoints are offered, so the editor can never author an out-of-bounds value
# (the validator is the ultimate guard for anything hand-crafted).
_controller_enter_partition_edit() {
  local line="$1" nav dev st cur nxt
  nav="$(_controller_navigation)"; dev="$(navigation_get "$nav" device)"; st="$(_controller_state)"
  case "$line" in
  "← Back") _controller_write_navigation "$(navigation_back "$nav")"; echo render; return ;;
  "mountpoint:"*)
    cur="$(_controller_manual_field "$st" "$dev" mountpoint)"
    nxt="$(manual_partition_cycle_mountpoint "$cur")"
    _controller_write_state "$(_controller_manual_set "$st" "$dev" mountpoint "$nxt")"
    echo refresh; return ;;
  "filesystem:"*)
    cur="$(_controller_manual_field "$st" "$dev" fs)"
    nxt="$(manual_partition_cycle_filesystem "$cur")"
    _controller_write_state "$(_controller_manual_set "$st" "$dev" fs "$nxt")"
    echo refresh; return ;;
  "format:"*)
    cur="$(_controller_manual_field "$st" "$dev" format)"
    [[ "$cur" == "true" ]] && nxt=false || nxt=true
    _controller_write_state "$(_controller_manual_set "$st" "$dev" format "$nxt")"
    echo refresh; return ;;
  *) echo noop ;;
  esac
}

_controller_enter_new_host() {
  local line="$1" nav; nav="$(_controller_navigation)"
  case "$line" in
  "Yes"*)
    _controller_new_host_reset
    _controller_write_navigation '{"screen":"top"}'
    echo render ;;
  *)
    _controller_write_navigation "$(navigation_back "$nav")"; echo render ;;
  esac
}

# _controller_enter_root_editor <line> — the Root Editor dispatch (ADR 0063): open the
# masked password capture (rich fzf) or its execute() fallback (older fzf), or
# cycle root's login shell into options.root_shell (strict delta — landing on
# the baseline shell drops the override, like the per-user cycle). Storage is
# unchanged from the old root rows; only the surface moved behind this editor.
_controller_enter_root_editor() {
  local line="$1" nav; nav="$(_controller_navigation)"
  case "$line" in
  "← Back")
    _controller_write_navigation "$(navigation_back "$nav")"; echo render; return ;;
  "password:"*)
    if _controller_rich_chrome; then _controller_open_secret root; else echo "secret-root"; fi
    return ;;
  "shell:"*)
    local _rc _rn
    _rc="$(_controller_root_shell_full)"
    _rn="$(_controller_cycle_next "$_rc" /bin/bash /bin/zsh /bin/fish)"
    if [[ "$_rn" == "$(_controller_root_shell_committed)" ]]; then
      _controller_write_state "$(config_state_unset "$(_controller_state)" options.root_shell)"
    else
      _controller_write_state \
        "$(edit_set_scalar "$(_controller_state)" options.root_shell "$_rn")"
    fi
    echo refresh; return ;;
  esac
  echo refresh
}

_controller_enter_category() {
  local line="$1" nav cat label path
  nav="$(_controller_navigation)"; cat="$(navigation_get "$nav" category)"
  case "$line" in
  "← Back")
    _controller_write_navigation "$(navigation_back "$nav")"; echo render; return ;;
  "Layout:"*)   # display_label "layout"
    # Manual Partitioning locks the pool-dependent Disks sub-editors (ADR 0073):
    # opening the layout editor is a no-op while it is on.
    manual_partition_kind_active "$(_controller_state)" && { echo render; return; }
    _controller_write_navigation "$(navigation_to_values "$cat" __layout__ "layout")"
    echo render; return ;;
  "Manual partitioning:"*)   # on/off toggle over disk_config.kind (ADR 0073)
    local _mst _mcur _mnew
    _mst="$(_controller_state)"; _mcur="$(config_state_get "$_mst" disk_config.kind)"
    [[ "$_mcur" == "manual" ]] && _mnew=auto || _mnew=manual
    _controller_write_state "$(_controller_apply_enum "$_mst" disk_config.kind "$_mnew")"
    # Turning it on: reload + a header notice pointing at the Partitions row.
    [[ "$_mnew" == "manual" ]] && { echo manual-on; return; }
    echo refresh; return ;;
  "Partitions ▸"*)   # Manual Partitioning: open the assignment table (ADR 0073)
    _controller_write_navigation "$(navigation_to_manual_partitions "$cat")"; echo render; return ;;
  "Swap:"*)     # display_label "swap"
    manual_partition_kind_active "$(_controller_state)" && { echo render; return; }
    _controller_write_navigation "$(navigation_to_swap_edit "$cat")"; echo render; return ;;
  "Root disk:"*)   # display_label "root disk"
    _controller_write_navigation "$(navigation_to_root_disk "$cat")"; echo render; return ;;
  "Encryption ▸"*)   # the collapsed Disks encryption row (ADR 0059)
    manual_partition_kind_active "$(_controller_state)" && { echo render; return; }
    _controller_write_navigation "$(navigation_to_encryption "$cat")"; echo render; return ;;
  "Impermanence ▸"*)   # the collapsed Disks impermanence row (ADR 0066)
    manual_partition_kind_active "$(_controller_state)" && { echo render; return; }
    _controller_write_navigation "$(navigation_to_impermanence "$cat")"; echo render; return ;;
  "repo ▸"* | "aur ▸"*)
    _controller_write_navigation "$(navigation_to_package_category "$cat" "${line%% *}")"
    echo render; return ;;
  "derived ▸"*)
    _controller_write_navigation "$(navigation_to_package_derived "$cat")"; echo render; return ;;
  esac
  label="${line%%:*}"
  path="$(_controller_field_for_label "$cat" "$label")"
  [[ -n "$path" ]] || { echo noop; return; }
  # A Cycle Field (bare bool) flips in place and stays on the category screen —
  # no values submenu (ADR 0075). Read the EFFECTIVE value (a default-true bool
  # with no override must read true), flip it through the strict-delta apply so
  # landing back on the default clears the override; a
  # Manual-Partitioning-locked
  # field is a silent no-op (the apply guard returns the state unchanged).
  if _controller_is_cycle_field "$path"; then
    local _cur _next _new
    _cur="$(menu_render_value \
      "$(_controller_effective "$(_controller_state)" "$(_controller_baseline)")" "$path")"
    [[ "$_cur" == true ]] && _next=false || _next=true
    if _new="$(_controller_apply_enum "$(_controller_state)" "$path" "$_next")"; then
      _controller_write_state "$(_controller_normalise_default "$_new" "$path")"
    fi
    echo refresh; return
  fi
  case "$(_controller_field_kind "$path")" in
  enum | toggle | list | users | biglist)
    _controller_write_navigation "$(navigation_to_values "$cat" "$path" "$label")"; echo render ;;
  text)
    _controller_write_navigation "$(navigation_to_text "$cat" "$path" "$label")"; echo render ;;
  *)
    echo noop ;;   # unreachable: _controller_field_kind returns only the kinds above
  esac
}
