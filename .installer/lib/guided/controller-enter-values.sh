#!/usr/bin/env bash
# =============================================================================
# lib/guided/controller-enter-values.sh — enter dispatch: values, text, encryption
# =============================================================================
# Part of the guided controller (lib/guided/controller.sh, ADR 0042).
#
# Used by: lib/guided/controller.sh (sources it).
# =============================================================================

_controller_enter_values() {
  local line="$1" navigation path kind
  navigation="$(_controller_navigation)"
  path="$(navigation_get "$navigation" field)"
  if [[ "$line" == "← Back" ]]; then
    _controller_write_navigation "$(navigation_back "$navigation")"
    echo render; return
  fi
  kind="$(_controller_field_kind "$path")"
  if [[ "$kind" == "toggle" ]]; then
    _controller_enter_toggle_value "$line" "$path"; return
  fi
  case "$path" in
  sysctl | options.mirror_servers | options.custom_repositories)
    _controller_enter_list_value "$line" "$navigation" "$path"; return ;;
  users)
    _controller_enter_users_value "$line" "$navigation"; return ;;
  esac
  if [[ "$kind" == "biglist" ]]; then
    _controller_enter_big_list_value "$line" "$navigation" "$path"; return
  fi
  if [[ "$path" == "__layout__" ]]; then
    _controller_enter_layout_value "$line" "$navigation"; return
  fi
  _controller_enter_enum_value "$line" "$navigation" "$path"
}

# _controller_enter_toggle_value <line> <path> — strip the "[x] "/"[ ] " mark,
# flip membership, and STAY on the screen so the operator can toggle several.
# `refresh` (reload-sync, query/header kept) re-marks the list in place
# without the flicker — and crucially without clearing a filter the operator
# typed on a long list (e.g. mirror countries).
_controller_enter_toggle_value() {
  local line="$1" path="$2" value="${1:4}"
  # Value-formattable toggles render options through the formatter, so map the
  # displayed option back to its stored (lower-case) value before flipping.
  if _controller_display_values "$path"; then
    local -a options; mapfile -t options < <(_controller_toggle_options "$path")
    value="$(display_reverse "$value" "${options[@]}")" || value="${line:4}"
  fi
  _controller_write_state "$(_controller_normalise_default \
    "$(_controller_toggle_multi "$(_controller_state)" \
      "$(_controller_baseline)" "$path" "$value")" "$path")"
  echo refresh
}

# _controller_enter_list_value <line> <navigation> <path> — sysctl, custom
# mirror servers and custom repositories (ADR 0072): "+ Add" opens the text
# editor; an existing entry is display-only (re-list in place).
_controller_enter_list_value() {
  local line="$1" navigation="$2" path="$3"
  if [[ "$line" == "+ Add"* ]]; then
    _controller_write_navigation "$(navigation_to_text \
      "$(navigation_get "$navigation" category)" "$path" "$path")"
    echo render; return
  fi
  echo refresh
}

# _controller_enter_users_value <line> <navigation> — the Users screen rows.
_controller_enter_users_value() {
  local line="$1" navigation="$2" category
  category="$(navigation_get "$navigation" category)"
  # The merged root row (ADR 0063) opens the Root Editor (password + shell),
  # symmetric with a user row opening its User Editor (its line is
  # "root — <shell> · pw <tag>").
  if [[ "$line" == "root — "* ]]; then
    _controller_write_navigation "$(navigation_to_root_editor "$category")"
    echo render; return
  fi
  # Per-user credential rows: on a capable fzf (rich chrome ≥ 0.62) enter the
  # inline masked screen (ADR 0051); on an older fzf fall back to the
  # execute() masked prompt (ADR 0049).
  if [[ "$line" == *"password ("* ]]; then
    local user="${line#*password (}"; user="${user%%)*}"
    if _controller_rich_chrome; then _controller_open_secret user "$user"
    else echo "secret-user $user"; fi
    return
  fi
  if [[ "$line" == "+ Create"* ]]; then
    _controller_write_navigation \
      "$(navigation_to_text "$category" __newuser__ "new user")"
    echo render; return
  fi
  # A user row opens its User Editor (ADR 0051): enable/disable + shell (and
  # the richer fields in slice 03) live there, not on the list. The row is
  # "name — shell · pw …" (enabled) or "name — disabled", so the name is the
  # text before the " — " separator.
  _controller_write_navigation \
    "$(navigation_to_user_edit "$category" "${line%% — *}")"
  echo render
}

# _controller_enter_big_list_value <line> <navigation> <path> — a big
# filterable list → set the picked value, then back. The locale projections
# recompose the canonical system.locale (ADR 0076); every other big list sets
# its own scalar path. Both normalise against their real path.
_controller_enter_big_list_value() {
  local line="$1" navigation="$2" path="$3"
  case "$path" in
  __language__ | __encoding__)
    _controller_write_state "$(_controller_normalise_default \
      "$(_controller_apply_locale_part "$(_controller_state)" "$path" \
        "$line")" system.locale)" ;;
  system.console_font)
    # Reject a font not installed on the medium (ADR 0076): an off-list value
    # is only ever a typo that breaks the console at boot. Stay on the screen.
    locale_source_console_fonts | grep -qxF "$line" || { echo noop; return; }
    _controller_write_state "$(_controller_normalise_default \
      "$(edit_set_scalar "$(_controller_state)" "$path" "$line")" "$path")" ;;
  *)
    _controller_write_state "$(_controller_normalise_default \
      "$(edit_set_scalar "$(_controller_state)" "$path" "$line")" "$path")" ;;
  esac
  _controller_write_navigation "$(navigation_back "$navigation")"; echo render
}

# _controller_enter_layout_value <line> <navigation> — the layout picker.
_controller_enter_layout_value() {
  local line="$1" navigation="$2" category skeleton
  category="$(navigation_get "$navigation" category)"
  if [[ "$line" == "data-pools" ]]; then
    # "data-pools" is the door to the editor (the pools live under layout, not
    # a separate row): seed one pool if there are none yet, then open the
    # editor.
    [[ "$(jq '(.data_pools // []) | length' <<<"$(_controller_state)")" \
        == "0" ]] \
      && _controller_write_state "$(_controller_add_data_pool \
        "$(_controller_state)")"
    _controller_write_navigation "$(navigation_to_data_pools "$category")"
    echo render; return
  fi
  if [[ "$line" == "custom…" ]]; then
    # blank-canvas seed → straight into the unified editor (ADR 0047).
    _controller_write_state \
      "$(edit_apply_skeleton "$(_controller_state)" "$(skeleton_custom_seed)")"
    _controller_write_navigation "$(navigation_to_data_pools "$category")"
    echo render; return
  fi
  if skeleton="$(skeleton_preset "$line" 2>/dev/null)"; then
    _controller_write_state \
      "$(edit_apply_skeleton "$(_controller_state)" "$skeleton")"
  fi
  # A multi preset drops into the unified editor to bind disks / tweak pools;
  # single applies and backs out to the category (ADR 0047).
  if [[ "$(jq -r '.mode // "single"' <<<"$(_controller_state)")" \
        == "multi" ]]; then
    _controller_write_navigation "$(navigation_to_data_pools "$category")"
  else
    _controller_write_navigation "$(navigation_back "$navigation")"
  fi
  echo render
}

# _controller_enter_enum_value <line> <navigation> <path> — an enum pick.
# Value-formattable enums render options through the formatter; reverse-map
# the picked display string back to its stored value.
_controller_enter_enum_value() {
  local line="$1" navigation="$2" path="$3" value="$1" updated
  if _controller_display_values "$path"; then
    local -a options; mapfile -t options < <(_controller_enum_options "$path")
    value="$(display_reverse "$line" "${options[@]}")" || value="$line"
  fi
  if updated="$(_controller_apply_enum "$(_controller_state)" "$path" \
       "$value")"; then
    _controller_write_state "$(_controller_normalise_default "$updated" \
      "$path")"
  fi
  _controller_write_navigation "$(navigation_back "$navigation")"; echo render
}

# _controller_enter_text <query> — commit the typed query into the field, then back.
# Empty query (Esc-less cancel via Enter) just returns without a change.
_controller_enter_text() {
  local query="$1" navigation path category
  navigation="$(_controller_navigation)"
  path="$(navigation_get "$navigation" field)"
  category="$(navigation_get "$navigation" category)"
  case "$path" in
  __poolmount__)
    _controller_enter_pool_mount "$query" "$navigation" "$category"; return ;;
  __newuser__)
    _controller_enter_new_user "$query" "$category"; return ;;
  __cloneuser__)
    _controller_enter_clone_user "$query" "$navigation" "$category"; return ;;
  esac
  [[ -n "$query" ]] \
    && _controller_write_state "$(_controller_normalise_default \
         "$(_controller_apply_text "$(_controller_state)" "$path" "$query")" \
         "$path")"
  _controller_text_return "$path" "$navigation" "$category"
  echo render
}

# _controller_text_return <path> <navigation> <category> — sysctl /
# create-user / persist came from a list or sub-editor screen, so return there
# (the new entry shows, more can be added); every other text field backs out.
_controller_text_return() {
  local path="$1" navigation="$2" category="$3"
  case "$path" in
  sysctl)
    _controller_write_navigation \
      "$(navigation_to_values "$category" sysctl sysctl)" ;;
  options.mirror_servers)
    _controller_write_navigation "$(navigation_to_values "$category" \
      options.mirror_servers "custom servers")" ;;
  options.custom_repositories)
    _controller_write_navigation "$(navigation_to_values "$category" \
      options.custom_repositories "custom repositories")" ;;
  __newuser__)
    _controller_write_navigation \
      "$(navigation_to_values "$category" users users)" ;;
  __persist__)
    _controller_write_navigation "$(navigation_to_impermanence "$category")" ;;
  options.swap_size)
    _controller_write_navigation "$(navigation_to_swap_edit "$category")" ;;
  *)
    _controller_write_navigation "$(navigation_back "$navigation")" ;;
  esac
}

# Pool mount is scoped to a data pool by the nav's index (ADR 0047): a typed
# value commits to .data_pools[index].mount; a blank input keeps the /<name>
# default (no key written). Either way return to that pool's editor.
_controller_enter_pool_mount() {
  local query="$1" navigation="$2" category="$3" index
  index="$(navigation_get "$navigation" index)"
  [[ -n "$query" ]] \
    && _controller_write_state "$(jq --argjson i "$index" --arg m "$query" \
      '.data_pools[$i].mount = $m' <<<"$(_controller_state)")"
  _controller_write_navigation \
    "$(navigation_to_pool_edit "$category" "$index" data)"
  echo render
}

# Create user (ADR 0051): a typed name that isn't a duplicate is added to the
# user list, seeded with the create defaults (bash / sudo on / wheel) in its
# install-scoped form, and the operator is dropped INTO the editor to set the
# required password and anything else. A blank name backs out; a duplicate
# (committed or already listed) is refused with a notice.
_controller_enter_new_user() {
  local name="$1" category="$2"
  _controller_accept_new_user_name "$name" "$category" || return 0
  _controller_append_user "$name"
  if [[ -n "${GUIDED_USERFORMS_FILE:-}" ]]; then
    guided_userform_set "$GUIDED_USERFORMS_FILE" "$name" shell \
      "$(jq -Rn --arg s "$(_controller_default_user_shell)" '$s')"
    guided_userform_set "$GUIDED_USERFORMS_FILE" "$name" sudo 'true'
    guided_userform_set "$GUIDED_USERFORMS_FILE" "$name" groups '["wheel"]'
  fi
  _controller_write_navigation "$(navigation_to_user_edit "$category" "$name")"
  echo render
}

# Clone user (ADR 0064): like create, but the new name is seeded with the
# SOURCE user's account-shape (carried on the nav). Same blank-backs-out and
# duplicate-refused rules, then drop INTO the clone's editor to set the pw.
_controller_enter_clone_user() {
  local name="$1" navigation="$2" category="$3" source_user
  source_user="$(navigation_get "$navigation" user)"
  _controller_accept_new_user_name "$name" "$category" || return 0
  _controller_append_user "$name"
  _controller_clone_seed "$source_user" "$name"
  _controller_write_navigation "$(navigation_to_user_edit "$category" "$name")"
  echo render
}

# _controller_accept_new_user_name <name> <category> — rc 0 for a fresh user
# name; a blank name backs out to the Users list and a duplicate (committed or
# already listed) prints a notice, both rc 1.
_controller_accept_new_user_name() {
  local name="$1" category="$2"
  if [[ -z "$name" ]]; then
    _controller_write_navigation \
      "$(navigation_to_values "$category" users users)"
    echo render; return 1
  fi
  if _controller_user_is_committed "$name" || jq -e --arg v "$name" \
      '(.users // []) | any(. == $v)' \
      <<<"$(_controller_effective "$(_controller_state)" \
        "$(_controller_baseline)")" >/dev/null; then
    echo "notice ⚠ user '${name}' already exists — pick another name"
    return 1
  fi
}

# _controller_append_user <name> — add <name> to the effective users list.
_controller_append_user() {
  local users_json
  users_json="$(jq -c '.users // []' <<<"$(_controller_effective \
    "$(_controller_state)" "$(_controller_baseline)")")"
  _controller_write_state "$(config_state_set "$(_controller_state)" users \
    "$(jq -cn --arg v "$1" --argjson a "$users_json" '$a + [$v]')")"
}

# _controller_enter_swap_edit <line> — the swap sub-editor: toggle swap on/off, toggle
# zswap, cycle the zswap compressor (zstd→lz4→lzo) and max pool % (5→…→60), or
# open the free-text size editor. Toggles/cycles STAY on the screen (refresh);
# size opens the text screen (which returns here — see _controller_enter_text).
# _controller_enter_encryption <line> — the Encryption Editor (ADR 0059): flip the
# enablement toggle in place (strict delta — landing back on the baseline drops
# the override), or drop the passphrase row into the shared masked capture (rich
# fzf enters the masked screen; older fzf falls back to the execute() prompt).
# The capture carries this screen as its origin, so a confirmed passphrase
# returns here. Setting a passphrase never touches the toggle.
_controller_enter_encryption() {
  local line="$1" nav; nav="$(_controller_navigation)"
  case "$line" in
  "← Back")
    _controller_write_navigation "$(navigation_back "$nav")"; echo render; return ;;
  "enabled:"*)
    # flip options.encryption; has() keeps an explicit value from being read as
    # the default (false). Normalise so toggling back to the baseline (off)
    # leaves no override, exactly like the values-screen edit.
    local _flipped
    _flipped="$(jq '
      (if (.options // {} | has("encryption")) then .options.encryption
       else false end) as $c
      | .options.encryption = ($c | not)' <<<"$(_controller_state)")"
    _controller_write_state "$(_controller_normalise_default "$_flipped" options.encryption)"
    echo refresh; return ;;
  "password:"*)
    if _controller_rich_chrome; then _controller_open_secret enc; else echo "secret-enc"; fi
    return ;;
  esac
  echo refresh
}

# _controller_enter_impermanence <line> — the Impermanence Editor dispatch (ADR 0066):
# flip options.impermanence.enabled in place (strict delta — landing on the
# baseline drops the override, like the encryption toggle) or open the
# __persist__ add-a-directory text screen. The read-only curated-defaults row
# is inert. Modelled on the encryption sub-editor.
_controller_enter_impermanence() {
  local line="$1" nav cat; nav="$(_controller_navigation)"; cat="$(navigation_get "$nav" category)"
  case "$line" in
  "← Back")
    _controller_write_navigation "$(navigation_back "$nav")"; echo render; return ;;
  "enabled:"*)
    local _flipped
    _flipped="$(jq '
      (if (.options.impermanence // {} | has("enabled"))
       then .options.impermanence.enabled else false end) as $c
      | .options.impermanence.enabled = ($c | not)' <<<"$(_controller_state)")"
    _controller_write_state \
      "$(_controller_normalise_default "$_flipped" options.impermanence.enabled)"
    echo refresh; return ;;
  "Add persist"*)
    _controller_write_navigation "$(navigation_to_text "$cat" __persist__ "persist dir")"
    echo render; return ;;
  "curated defaults:"*)
    echo refresh; return ;;   # read-only summary line
  esac
  # Any other row is a user-added persist directory (ADR 0066): drop it. A stray
  # line that isn't in the list is a harmless no-op (edit returns it unchanged).
  _controller_write_state "$(edit_remove_persist "$(_controller_state)" "$line" || true)"
  echo refresh
}
