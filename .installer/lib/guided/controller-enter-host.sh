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
  "Profiles ▸"*)    _controller_write_navigation \
    "$(navigation_to_profiles)"; echo render ;;
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
      _controller_write_navigation \
        "$(navigation_to_values Users users users)"; echo render
    elif menu_categories "$(_controller_state)" "$(_controller_baseline)" \
         | jq -e --arg c "$cat" 'any(.[]; .name == $c)' >/dev/null 2>&1; then
      _controller_write_navigation \
        "$(navigation_to_category "$cat")"; echo render
    else
      echo noop
    fi ;;
  esac
}

# _controller_enter_profiles <line> — Enter on the Profiles screen (ADR 0055).
# `← Back` returns to the top screen unchanged. A profile row SEEDS the menu:
# the chosen hosts/<name>/profile.jsonc is parsed and merged over the current
# Config State (profiles_seed — profile wins, devices flattened), so every
# category reflects it, then nav returns to the top screen for tweak-or-Proceed.
# A profile that fails to parse leaves the state untouched and warns via a
# notice.
_controller_enter_profiles() {
  local line="$1" navigation profile_file profile
  navigation="$(_controller_navigation)"
  if [[ "$line" == "← Back" ]]; then
    _controller_write_navigation \
      "$(navigation_back "$navigation")"; echo render; return
  fi
  # `↺ Reset to blank` (ADR 0063): a full session reset is destructive,
  # so drill into a confirm screen rather than resetting on the spot.
  if [[ "$line" == "↺ Reset to blank"* ]]; then
    _controller_write_navigation \
      "$(navigation_to_new_host)"; echo render; return
  fi
  profile_file="$(_controller_hosts_root)/${line}/profile.jsonc"
  if ! profile="$(_program_registry_parse "$profile_file" 2>/dev/null)"; then
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

# _controller_session_stash — snapshot the pre-reset session side-state
# (per-user editor forms + the password/secret manifest) into
# GUIDED_SESSION_UNDO_FILE, so a single undo after a `+ New host` reset can
# restore it. The Config State is already undoable through the history stack;
# this covers only the two side files the stack does not. No-op when no undo
# file is wired (non-persistent).
_controller_session_stash() {
  [[ -n "${GUIDED_SESSION_UNDO_FILE:-}" ]] || return 0
  local userforms='{}' secrets='{}'
  [[ -s "${GUIDED_USERFORMS_FILE:-}" ]] \
    && userforms="$(<"$GUIDED_USERFORMS_FILE")"
  [[ -s "${GUIDED_SECRETS_FILE:-}" ]] && secrets="$(<"$GUIDED_SECRETS_FILE")"
  jq -n --argjson u "$userforms" --argjson s \
    "$secrets" '{userforms:$u, secrets:$s}' \
    >"$GUIDED_SESSION_UNDO_FILE"
}

# _controller_session_unstash — restore the userforms + secrets files from the
# stash and drop it. Called by the first undo after a `+ New host` reset. No-op
# when the stash is absent/empty (nothing to restore).
_controller_session_unstash() {
  [[ -s "${GUIDED_SESSION_UNDO_FILE:-/nonexistent}" ]] || return 0
  local stash; stash="$(<"$GUIDED_SESSION_UNDO_FILE")"
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] \
    && jq -c '.userforms // {}' <<<"$stash" >"$GUIDED_USERFORMS_FILE"
  [[ -n "${GUIDED_SECRETS_FILE:-}" ]] \
    && jq -c '.secrets // {}' <<<"$stash" >"$GUIDED_SECRETS_FILE"
  rm -f "$GUIDED_SESSION_UNDO_FILE"
}

# _controller_new_host_reset — the `+ New host` full session reset (ADR 0063).
# Broader than Reset-all (which clears Config State only): it returns Config
# State to the Host Core baseline (a `{}` override map — like ^R, and recorded
# on the undo stack) AND clears the session-created users' editor forms and the
# secret / password manifest overrides (the in-menu disk bindings live in Config
# State, so the `{}` reset drops them too). The side files are stashed first, so
# a single undo restores the whole pre-reset session.
_controller_new_host_reset() {
  _controller_session_stash
  if [[ -f "${GUIDED_HIST_FILE:-/nonexistent}" ]]; then
    local history; history="$(<"$GUIDED_HIST_FILE")"
    history="$(history_commit "$history" '{}')"
    printf '%s\n' "$history" >"$GUIDED_HIST_FILE"
    _controller_write_state "$(history_present "$history")"
  else
    _controller_write_state '{}'
  fi
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] \
    && printf '{}\n' >"$GUIDED_USERFORMS_FILE"
  [[ -n "${GUIDED_SECRETS_FILE:-}" ]] && printf '{}\n' >"$GUIDED_SECRETS_FILE"
}

# _controller_enter_new_host <line> — the `+ New host` confirm screen (ADR
# 0063): the confirm row runs the full session reset and returns to a blank top
# screen; any other row (← Back) cancels back to the picker, session work
# intact. _controller_manual_set <state> <device> <field> <value> → state with
# one field of the partition <device> changed (via the pure
# manual_partition_set_field), re-stored under disk_config.partitions. The
# single write path the assignment editor uses.
_controller_manual_set() {
  local state="$1" dev="$2" field="$3" value="$4" parts
  parts="$(config_state_get "$state" disk_config.partitions)"
  manual_partition_store "$state" \
    "$(manual_partition_set_field "${parts:-[]}" "$dev" "$field" "$value")"
}

# _controller_manual_field <state> <device> <field> → the current value of
# <field> on the partition <device> (empty when unset).
_controller_manual_field() {
  jq -r --arg d "$2" --arg f "$3" '
    (.disk_config.partitions // [])[]
    | select(.device == $d) | (.[$f] // "")
  ' <<< "$1"
}

# _controller_enter_manual_partitions <line> — the assignment table: the cfdisk
# hand-off action, then one row per partition (opens its editor). cfdisk is
# gated in --debug (ADR 0063: inspect-only, no disk touched).
_controller_enter_manual_partitions() {
  local line="$1" navigation cat; navigation="$(_controller_navigation)"; \
    cat="$(navigation_get "$navigation" category)"
  case "$line" in
  "← Back") _controller_write_navigation \
    "$(navigation_back "$navigation")"; echo render; return ;;
  "⟳ Run cfdisk"*)
    [[ "${INSTALL_DEBUG:-0}" == "1" ]] \
      && { echo 'notice cfdisk is disabled in --debug — no disk is touched'
           return; }
    echo cfdisk; return ;;
  "/dev/"*)
    local dev="${line%%  *}"
    _controller_write_navigation \
      "$(navigation_to_partition_edit "$cat" "$dev")"; echo render; return ;;
  *) echo noop ;;
  esac
}

# _controller_enter_partition_edit <line> — the per-partition editor: Enter
# cycles the mountpoint / filesystem, or toggles format. Only supported
# filesystems and mountpoints are offered, so the editor can never author an
# out-of-bounds value (the validator is the ultimate guard for anything
# hand-crafted).
_controller_enter_partition_edit() {
  local line="$1" navigation dev state current nxt
  navigation="$(_controller_navigation)"; \
    dev="$(navigation_get "$navigation" device)"; state="$(_controller_state)"
  case "$line" in
  "← Back") _controller_write_navigation \
    "$(navigation_back "$navigation")"; echo render; return ;;
  "mountpoint:"*)
    current="$(_controller_manual_field "$state" "$dev" mountpoint)"
    nxt="$(manual_partition_cycle_mountpoint "$current")"
    _controller_write_state \
      "$(_controller_manual_set "$state" "$dev" mountpoint "$nxt")"
    echo refresh; return ;;
  "filesystem:"*)
    current="$(_controller_manual_field "$state" "$dev" fs)"
    nxt="$(manual_partition_cycle_filesystem "$current")"
    _controller_write_state \
      "$(_controller_manual_set "$state" "$dev" fs "$nxt")"
    echo refresh; return ;;
  "format:"*)
    current="$(_controller_manual_field "$state" "$dev" format)"
    [[ "$current" == "true" ]] && nxt=false || nxt=true
    _controller_write_state \
      "$(_controller_manual_set "$state" "$dev" format "$nxt")"
    echo refresh; return ;;
  *) echo noop ;;
  esac
}

_controller_enter_new_host() {
  local line="$1" navigation; navigation="$(_controller_navigation)"
  case "$line" in
  "Yes"*)
    _controller_new_host_reset
    _controller_write_navigation '{"screen":"top"}'
    echo render ;;
  *)
    _controller_write_navigation \
      "$(navigation_back "$navigation")"; echo render ;;
  esac
}

# _controller_enter_root_editor <line> — the Root Editor dispatch (ADR 0063):
# open the masked password capture (rich fzf) or its execute() fallback (older
# fzf), or cycle root's login shell into options.root_shell (strict delta —
# landing on the baseline shell drops the override, like the per-user cycle).
# Storage is unchanged from the old root rows; only the surface moved behind
# this editor.
_controller_enter_root_editor() {
  local line="$1" navigation; navigation="$(_controller_navigation)"
  case "$line" in
  "← Back")
    _controller_write_navigation \
      "$(navigation_back "$navigation")"; echo render; return ;;
  "password:"*)
    if _controller_rich_chrome; then _controller_open_secret root; else echo \
      "secret-root"; fi
    return ;;
  "shell:"*)
    local current_shell next_shell
    current_shell="$(_controller_root_shell_full)"
    next_shell="$(_controller_cycle_next "$current_shell" \
      /bin/bash /bin/zsh /bin/fish)"
    if [[ "$next_shell" == "$(_controller_root_shell_committed)" ]]; then
      _controller_write_state \
        "$(config_state_unset "$(_controller_state)" options.root_shell)"
    else
      _controller_write_state \
        "$(edit_set_scalar "$(_controller_state)" options.root_shell \
          "$next_shell")"
    fi
    echo refresh; return ;;
  esac
  echo refresh
}

_controller_enter_category() {
  local line="$1" navigation category label path
  navigation="$(_controller_navigation)"
  category="$(navigation_get "$navigation" category)"
  _controller_enter_category_row "$line" "$navigation" "$category" && return
  label="${line%%:*}"
  path="$(_controller_field_for_label "$category" "$label")"
  [[ -n "$path" ]] || { echo noop; return; }
  if _controller_is_cycle_field "$path"; then
    _controller_cycle_bool_field "$path"; return
  fi
  case "$(_controller_field_kind "$path")" in
  enum | toggle | list | users | biglist)
    _controller_write_navigation \
      "$(navigation_to_values "$category" "$path" "$label")"
    echo render ;;
  text)
    _controller_write_navigation \
      "$(navigation_to_text "$category" "$path" "$label")"
    echo render ;;
  *)
    echo noop ;; \
        # unreachable: _controller_field_kind returns only the kinds above
  esac
}

# _controller_enter_category_row <line> <navigation> <category> — the
# category screen's non-field rows (back, layout, drill-downs); rc 1 for a
# field row.
_controller_enter_category_row() {
  local line="$1" navigation="$2" category="$3" target
  case "$line" in
  "← Back") target="$(navigation_back "$navigation")" ;;
  "Layout:"*)   # display_label "layout"
    # Manual Partitioning locks the pool-dependent Disks sub-editors (ADR
    # 0073): opening the layout editor is a no-op while it is on.
    manual_partition_kind_active "$(_controller_state)" \
      && { echo render; return 0; }
    target="$(navigation_to_values "$category" __layout__ "layout")" ;;
  "Manual partitioning:"*)   # on/off toggle over disk_config.kind (ADR 0073)
    _controller_toggle_manual_partitioning; return 0 ;;
  "Partitions ▸"*)   # Manual Partitioning: open the assignment table (ADR 0073)
    target="$(navigation_to_manual_partitions "$category")" ;;
  "Swap:"*)     # display_label "swap"
    manual_partition_kind_active "$(_controller_state)" \
      && { echo render; return 0; }
    target="$(navigation_to_swap_edit "$category")" ;;
  "Root disk:"*)   # display_label "root disk"
    target="$(navigation_to_root_disk "$category")" ;;
  "Encryption ▸"*)   # the collapsed Disks encryption row (ADR 0059)
    manual_partition_kind_active "$(_controller_state)" \
      && { echo render; return 0; }
    target="$(navigation_to_encryption "$category")" ;;
  "Impermanence ▸"*)   # the collapsed Disks impermanence row (ADR 0066)
    manual_partition_kind_active "$(_controller_state)" \
      && { echo render; return 0; }
    target="$(navigation_to_impermanence "$category")" ;;
  "repo ▸"* | "aur ▸"*)
    target="$(navigation_to_package_category "$category" "${line%% *}")" ;;
  "derived ▸"*)
    target="$(navigation_to_package_derived "$category")" ;;
  *) return 1 ;;
  esac
  _controller_write_navigation "$target"
  echo render
}

# _controller_toggle_manual_partitioning — flip disk_config.kind auto ↔
# manual. Turning it on: reload + a header notice pointing at the Partitions
# row.
_controller_toggle_manual_partitioning() {
  local state current updated
  state="$(_controller_state)"
  current="$(config_state_get "$state" disk_config.kind)"
  [[ "$current" == "manual" ]] && updated=auto || updated=manual
  _controller_write_state \
    "$(_controller_apply_enum "$state" disk_config.kind "$updated")"
  [[ "$updated" == "manual" ]] && { echo manual-on; return; }
  echo refresh
}

# _controller_cycle_bool_field <path> — a Cycle Field (bare bool) flips in
# place and stays on the category screen — no values submenu (ADR 0075). Read
# the EFFECTIVE value (a default-true bool with no override must read true),
# flip it through the strict-delta apply so landing back on the default clears
# the override; a Manual-Partitioning-locked field is a silent no-op (the apply
# guard returns the state unchanged).
_controller_cycle_bool_field() {
  local path="$1" current next updated
  current="$(menu_render_value "$(_controller_effective "$(_controller_state)" \
    "$(_controller_baseline)")" "$path")"
  [[ "$current" == true ]] && next=false || next=true
  if updated="$(_controller_apply_enum "$(_controller_state)" "$path" \
       "$next")"; then
    _controller_write_state "$(_controller_normalise_default "$updated" \
      "$path")"
  fi
  echo refresh
}
