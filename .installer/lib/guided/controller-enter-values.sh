#!/usr/bin/env bash
# =============================================================================
# lib/guided/controller-enter-values.sh — enter dispatch: values, text, encryption
# =============================================================================
# Part of the guided controller (lib/guided/controller.sh, ADR 0042).
#
# Used by: lib/guided/controller.sh (sources it).
# =============================================================================

_ctl_enter_values() {
  local line="$1" nav path sk new
  nav="$(_ctl_nav)"; path="$(navigation_get "$nav" field)"
  if [[ "$line" == "← Back" ]]; then
    _ctl_write_nav "$(navigation_back "$nav")"; echo render; return
  fi
  if [[ "$(_ctl_field_kind "$path")" == "toggle" ]]; then
    # strip the "[x] "/"[ ] " mark, flip membership, and STAY on the screen so
    # the operator can toggle several. `refresh` (reload-sync, query/header
    # kept)
    # re-marks the list in place without the flicker — and crucially without
    # clearing a filter the operator typed on a long list (e.g. mirror
    # countries).
    local _tval="${line:4}"   # strip the "[x] "/"[ ] " mark
    # Value-formattable toggles render options through the formatter, so map the
    # displayed option back to its stored (lower-case) value before flipping.
    if _ctl_display_values "$path"; then
      local -a _opts; mapfile -t _opts < <(_ctl_toggle_options "$path")
      _tval="$(display_reverse "$_tval" "${_opts[@]}")" || _tval="${line:4}"
    fi
    _ctl_write_state "$(_ctl_normalise_default "$(_ctl_toggle_multi \
      "$(_ctl_state)" "$(_ctl_baseline)" "$path" "$_tval")" "$path")"
    echo refresh; return
  fi
  if [[ "$path" == "sysctl" ]]; then
    if [[ "$line" == "+ Add"* ]]; then
      _ctl_write_nav "$(navigation_to_text "$(navigation_get "$nav" category)" sysctl sysctl)"
      echo render; return
    fi
    echo refresh; return   # an existing pair is display-only (re-list in place)
  fi
  # Custom mirror servers / custom repositories (ADR 0072): "+ Add" opens the
  # text editor; an existing entry is display-only (re-list in place).
  if [[ "$path" == "options.mirror_servers" \
        || "$path" == "options.custom_repositories" ]]; then
    if [[ "$line" == "+ Add"* ]]; then
      _ctl_write_nav \
        "$(navigation_to_text "$(navigation_get "$nav" category)" "$path" "$path")"
      echo render; return
    fi
    echo refresh; return
  fi
  if [[ "$path" == "users" ]]; then
    # The merged root row (ADR 0063) opens the Root Editor (password + shell),
    # symmetric with a user row opening its User Editor. Handle it before the
    # toggle / user-row logic (its line is "root — <shell> · pw <tag>").
    if [[ "$line" == "root — "* ]]; then
      _ctl_write_nav "$(navigation_to_root_editor "$(navigation_get "$nav" category)")"
      echo render; return
    fi
    # Per-user credential rows: on a capable fzf (rich chrome ≥ 0.62) enter the
    # inline masked screen (ADR 0051); on an older fzf fall back to the
    # execute() masked prompt (ADR 0049). Handle before the toggle logic.
    if [[ "$line" == *"password ("* ]]; then
      local _sn="${line#*password (}"; _sn="${_sn%%)*}"
      if _ctl_rich_chrome; then _ctl_open_secret user "$_sn"
      else echo "secret-user $_sn"; fi
      return
    fi
    if [[ "$line" == "+ Create"* ]]; then
      _ctl_write_nav \
        "$(navigation_to_text "$(navigation_get "$nav" category)" __newuser__ "new user")"
      echo render; return
    fi
    # A user row opens its User Editor (ADR 0051): enable/disable + shell (and
    # the
    # richer fields in slice 03) live there, not on the list. The row is
    # "name — shell · pw …" (enabled) or "name — disabled", so the name is the
    # text before the " — " separator.
    local _uname="${line%% — *}"
    _ctl_write_nav "$(navigation_to_user_edit "$(navigation_get "$nav" category)" "$_uname")"
    echo render; return
  fi
  if [[ "$(_ctl_field_kind "$path")" == "biglist" ]]; then
    # a big filterable list → set the picked value, then back. The locale
    # projections recompose the canonical system.locale (ADR 0076); every other
    # biglist sets its own scalar path. Both normalise against their real path.
    case "$path" in
    __language__ | __encoding__)
      _ctl_write_state "$(_ctl_normalise_default \
        "$(_ctl_apply_locale_part "$(_ctl_state)" "$path" "$line")" \
        system.locale)" ;;
    system.console_font)
      # Reject a font not installed on the medium (ADR 0076): an off-list value
      # is
      # only ever a typo that breaks the console at boot. Stay on the screen.
      locale_source_console_fonts | grep -qxF "$line" || { echo noop; return; }
      _ctl_write_state "$(_ctl_normalise_default \
        "$(edit_set_scalar "$(_ctl_state)" "$path" "$line")" "$path")" ;;
    *)
      _ctl_write_state "$(_ctl_normalise_default \
        "$(edit_set_scalar "$(_ctl_state)" "$path" "$line")" "$path")" ;;
    esac
    _ctl_write_nav "$(navigation_back "$nav")"; echo render; return
  fi
  if [[ "$path" == "__layout__" ]]; then
    if [[ "$line" == "data-pools" ]]; then
      # "data-pools" is the door to the editor (the pools live under layout, not
      # a
      # separate row): seed one pool if there are none yet, then open the
      # editor.
      [[ "$(jq '(.data_pools // []) | length' <<<"$(_ctl_state)")" == "0" ]] \
        && _ctl_write_state "$(_ctl_add_data_pool "$(_ctl_state)")"
      _ctl_write_nav "$(navigation_to_data_pools "$(navigation_get "$nav" category)")"
      echo render; return
    fi
    if [[ "$line" == "custom…" ]]; then
      # blank-canvas seed → straight into the unified editor (ADR 0047).
      _ctl_write_state \
        "$(edit_apply_skeleton "$(_ctl_state)" "$(skeleton_custom_seed)")"
      _ctl_write_nav "$(navigation_to_data_pools "$(navigation_get "$nav" category)")"
      echo render; return
    fi
    if sk="$(skeleton_preset "$line" 2>/dev/null)"; then
      _ctl_write_state "$(edit_apply_skeleton "$(_ctl_state)" "$sk")"
    fi
    # A multi preset drops into the unified editor to bind disks / tweak pools;
    # single applies and backs out to the category (ADR 0047).
    if [[ "$(jq -r '.mode // "single"' <<<"$(_ctl_state)")" == "multi" ]]; then
      _ctl_write_nav "$(navigation_to_data_pools "$(navigation_get "$nav" category)")"
    else
      _ctl_write_nav "$(navigation_back "$nav")"
    fi
    echo render; return
  fi
  local _eval="$line"
  # Value-formattable enums render options through the formatter; reverse-map
  # the picked display string back to its stored value.
  if _ctl_display_values "$path"; then
    local -a _eopts; mapfile -t _eopts < <(_ctl_enum_options "$path")
    _eval="$(display_reverse "$line" "${_eopts[@]}")" || _eval="$line"
  fi
  if new="$(_ctl_apply_enum "$(_ctl_state)" "$path" "$_eval")"; then
    _ctl_write_state "$(_ctl_normalise_default "$new" "$path")"
  fi
  _ctl_write_nav "$(navigation_back "$nav")"; echo render
}

# _ctl_enter_text <query> — commit the typed query into the field, then back.
# Empty query (Esc-less cancel via Enter) just returns without a change.
_ctl_enter_text() {
  local query="$1" nav path cat
  nav="$(_ctl_nav)"; path="$(navigation_get "$nav" field)"
  cat="$(navigation_get "$nav" category)"
  # Pool mount is scoped to a data pool by the nav's index (ADR 0047): a typed
  # value commits to .data_pools[index].mount; a blank input keeps the /<name>
  # default (no key written). Either way return to that pool's editor.
  if [[ "$path" == "__poolmount__" ]]; then
    local idx; idx="$(navigation_get "$nav" index)"
    [[ -n "$query" ]] \
      && _ctl_write_state "$(jq --argjson i "$idx" --arg m "$query" \
      '.data_pools[$i].mount = $m' <<<"$(_ctl_state)")"
    _ctl_write_nav "$(navigation_to_pool_edit "$cat" "$idx" data)"; echo render; return
  fi
  # Create user (ADR 0051): a typed name that isn't a duplicate is added to the
  # user list, seeded with the create defaults (bash / sudo on / wheel) in its
  # install-scoped form, and the operator is dropped INTO the editor to set the
  # required password and anything else. A blank name backs out; a duplicate
  # (committed or already listed) is refused with a notice.
  if [[ "$path" == "__newuser__" ]]; then
    [[ -n "$query" ]] || { _ctl_write_nav "$(navigation_to_values "$cat" users users)"
                           echo render; return; }
    if _ctl_user_is_committed "$query" || jq -e --arg v "$query" \
        '(.users // []) | any(. == $v)' \
        <<<"$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")" \
        >/dev/null; then
      echo "notice ⚠ user '${query}' already exists — pick another name"; return
    fi
    _ctl_write_state "$(config_state_set "$(_ctl_state)" users \
      "$(jq -cn --arg v "$query" --argjson a \
        "$(jq -c '.users // []' \
          <<<"$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")")" \
          '$a + [$v]')")"
    if [[ -n "${GUIDED_USERFORMS_FILE:-}" ]]; then
      guided_userform_set "$GUIDED_USERFORMS_FILE" "$query" shell \
        "$(jq -Rn --arg s "$(_ctl_default_user_shell)" '$s')"
      guided_userform_set "$GUIDED_USERFORMS_FILE" "$query" sudo 'true'
      guided_userform_set "$GUIDED_USERFORMS_FILE" "$query" groups '["wheel"]'
    fi
    _ctl_write_nav "$(navigation_to_user_edit "$cat" "$query")"; echo render; return
  fi
  # Clone user (ADR 0064): like create, but the new name is seeded with the
  # SOURCE user's account-shape (carried on the nav). Same blank-backs-out and
  # duplicate-refused rules, then drop INTO the clone's editor to set the pw.
  if [[ "$path" == "__cloneuser__" ]]; then
    local _src _eff; _src="$(navigation_get "$nav" user)"
    _eff="$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")"
    [[ -n "$query" ]] || { _ctl_write_nav "$(navigation_to_values "$cat" users users)"
                           echo render; return; }
    if _ctl_user_is_committed "$query" || jq -e --arg v "$query" \
        '(.users // []) | any(. == $v)' <<<"$_eff" >/dev/null; then
      echo "notice ⚠ user '${query}' already exists — pick another name"; return
    fi
    _ctl_write_state "$(config_state_set "$(_ctl_state)" users \
      "$(jq -cn --arg v "$query" --argjson a "$(jq -c '.users // []' \
        <<<"$_eff")" '$a + [$v]')")"
    _ctl_clone_seed "$_src" "$query"
    _ctl_write_nav "$(navigation_to_user_edit "$cat" "$query")"; echo render; return
  fi
  [[ -n "$query" ]] \
    && _ctl_write_state "$(_ctl_normalise_default \
         "$(_ctl_apply_text "$(_ctl_state)" "$path" "$query")" "$path")"
  # sysctl / create-user / persist came from a list or sub-editor screen, so
  # return there (the new entry shows, more can be added); every other text
  # field backs out.
  case "$path" in
  sysctl)            _ctl_write_nav "$(navigation_to_values "$cat" sysctl sysctl)" ;;
  options.mirror_servers)
    _ctl_write_nav "$(navigation_to_values "$cat" options.mirror_servers \
      "custom servers")" ;;
  options.custom_repositories)
    _ctl_write_nav "$(navigation_to_values "$cat" options.custom_repositories \
      "custom repositories")" ;;
  __newuser__)       _ctl_write_nav "$(navigation_to_values "$cat" users users)" ;;
  __persist__)       _ctl_write_nav "$(navigation_to_impermanence "$cat")" ;;
  options.swap_size) _ctl_write_nav "$(navigation_to_swap_edit "$cat")" ;;
  *)                 _ctl_write_nav "$(navigation_back "$nav")" ;;
  esac
  echo render
}

# _ctl_enter_swapedit <line> — the swap sub-editor: toggle swap on/off, toggle
# zswap, cycle the zswap compressor (zstd→lz4→lzo) and max pool % (5→…→60), or
# open the free-text size editor. Toggles/cycles STAY on the screen (refresh);
# size opens the text screen (which returns here — see _ctl_enter_text).
# _ctl_enter_encryption <line> — the Encryption Editor (ADR 0059): flip the
# enablement toggle in place (strict delta — landing back on the baseline drops
# the override), or drop the passphrase row into the shared masked capture (rich
# fzf enters the masked screen; older fzf falls back to the execute() prompt).
# The capture carries this screen as its origin, so a confirmed passphrase
# returns here. Setting a passphrase never touches the toggle.
_ctl_enter_encryption() {
  local line="$1" nav; nav="$(_ctl_nav)"
  case "$line" in
  "← Back")
    _ctl_write_nav "$(navigation_back "$nav")"; echo render; return ;;
  "enabled:"*)
    # flip options.encryption; has() keeps an explicit value from being read as
    # the default (false). Normalise so toggling back to the baseline (off)
    # leaves no override, exactly like the values-screen edit.
    local _flipped
    _flipped="$(jq '
      (if (.options // {} | has("encryption")) then .options.encryption
       else false end) as $c
      | .options.encryption = ($c | not)' <<<"$(_ctl_state)")"
    _ctl_write_state "$(_ctl_normalise_default "$_flipped" options.encryption)"
    echo refresh; return ;;
  "password:"*)
    if _ctl_rich_chrome; then _ctl_open_secret enc; else echo "secret-enc"; fi
    return ;;
  esac
  echo refresh
}

# _ctl_enter_impermanence <line> — the Impermanence Editor dispatch (ADR 0066):
# flip options.impermanence.enabled in place (strict delta — landing on the
# baseline drops the override, like the encryption toggle) or open the
# __persist__ add-a-directory text screen. The read-only curated-defaults row
# is inert. Modelled on the encryption sub-editor.
_ctl_enter_impermanence() {
  local line="$1" nav cat; nav="$(_ctl_nav)"; cat="$(navigation_get "$nav" category)"
  case "$line" in
  "← Back")
    _ctl_write_nav "$(navigation_back "$nav")"; echo render; return ;;
  "enabled:"*)
    local _flipped
    _flipped="$(jq '
      (if (.options.impermanence // {} | has("enabled"))
       then .options.impermanence.enabled else false end) as $c
      | .options.impermanence.enabled = ($c | not)' <<<"$(_ctl_state)")"
    _ctl_write_state \
      "$(_ctl_normalise_default "$_flipped" options.impermanence.enabled)"
    echo refresh; return ;;
  "Add persist"*)
    _ctl_write_nav "$(navigation_to_text "$cat" __persist__ "persist dir")"
    echo render; return ;;
  "curated defaults:"*)
    echo refresh; return ;;   # read-only summary line
  esac
  # Any other row is a user-added persist directory (ADR 0066): drop it. A stray
  # line that isn't in the list is a harmless no-op (edit returns it unchanged).
  _ctl_write_state "$(edit_remove_persist "$(_ctl_state)" "$line" || true)"
  echo refresh
}
