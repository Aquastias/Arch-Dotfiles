#!/usr/bin/env bash
# =============================================================================
# lib/guided/controller-user-fields.sh — user + root fields, sysctl lines, labels
# =============================================================================
# Part of the guided controller (lib/guided/controller.sh, ADR 0042).
#
# Used by: lib/guided/controller.sh (sources it).
# =============================================================================

# _controller_sysctl_lines <state> <base> → the current sysctl pairs
# ("key=value"), one per line, from the effective view (so the seeded
# vm.swappiness=10 shows up).
_controller_sysctl_lines() {
  jq -r '(.sysctl // {}) | to_entries[] | "\(.key)=\(.value)"' \
    <<<"$(_controller_effective "$1" "$2")"
}

# _controller_user_names → committed user names (users/<name>/profile.jsonc,
# minus core and the `vm-*` harness fixtures — ADR 0035 throwaway smoke-test
# users have no place in an operator's menu, mirroring profiles_list's core/vm
# skip).
_controller_user_names() {
  local user_directory user
  for user_directory in "${INSTALLER_DIR:-.}"/users/*/; do
    [[ -d "$user_directory" ]] || continue
    user="${user_directory%/}"
    user="${user##*/}"
    [[ "$user" == "core" || "$user" == vm-* ]] && continue
    [[ -f "${user_directory}profile.jsonc" ]] && printf '%s\n' "$user"
  done
}

# _controller_default_user_shell — the login shell an ad-hoc user gets: User
# Core's declared shell, else /bin/zsh. Reading User Core rather than hardcoding
# keeps the guided default in step with the committed base (ADR 0056 curation),
# so a name typed into the menu lands in the same shell a declared user would.
_controller_default_user_shell() {
  local shell="" core_profile="${INSTALLER_DIR:-}/users/core/profile.jsonc"
  [[ -n "${INSTALLER_DIR:-}" && -f "$core_profile" ]] \
    && shell="$(_program_registry_parse "$core_profile" 2>/dev/null \
          | jq -r '.shell // empty' 2>/dev/null)"
  printf '%s' "${shell:-/bin/zsh}"
}

# _controller_user_shell_full <name> — the effective login shell PATH: the User
# Editor's
# install-scoped override (userforms file) if set, else the committed User
# Profile's shell merged over User Core, else the User Core default (an ad-hoc
# name with no committed profile). The single source of truth the list display,
# the editor row, and the shell cycle all read.
_controller_user_shell_full() {
  local user="$1" shell=""
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] \
    && shell="$(guided_userform_field "$GUIDED_USERFORMS_FILE" "$user" shell)"
  if [[ -z "$shell" && -n "${INSTALLER_DIR:-}" \
     && -f "${INSTALLER_DIR}/users/${user}/profile.jsonc" ]]; then
    shell="$(profile_loader_load_user "$user" 2>/dev/null \
      | jq -r '.shell // empty' 2>/dev/null)"
  fi
  [[ -n "$shell" ]] || shell="$(_controller_default_user_shell)"
  printf '%s' "$shell"
}

# _controller_user_shell <name> — the short login shell (basename) for the list
# row.
_controller_user_shell() {
  local shell; shell="$(_controller_user_shell_full "$1")"
  printf '%s' "${shell##*/}"
}

# _controller_root_shell_full — root's effective login shell PATH (ADR 0054):
# the Config State override (options.root_shell) merged over the baseline, else
# the baseline's, else /bin/bash. The single source the Users row + the cycle
# read.
_controller_root_shell_full() {
  local shell
  shell="$(install_config_from_json "$(_controller_live_effective)" root_shell)"
  printf '%s' "$shell"
}

# _controller_root_shell — root's short login shell (basename) for the Users
# row.
_controller_root_shell() {
  local shell; shell="$(_controller_root_shell_full)"; printf '%s' \
    "${shell##*/}"
}

# _controller_root_shell_committed — the baseline (launch-state) root shell, or
# /bin/bash. The strict-delta reference: cycling onto it drops the override.
_controller_root_shell_committed() {
  install_config_from_json "$(_controller_baseline)" root_shell
}

# _controller_user_is_committed <name> — rc 0 when the user has a committed
# profile (users/<name>/profile.jsonc under INSTALLER_DIR): the editor shows
# `enabled` for those and `✗ remove user` for a session-created (ad-hoc) name
# instead.
_controller_user_is_committed() {
  [[ -n "${INSTALLER_DIR:-}" && -f "${INSTALLER_DIR}/users/${1}/profile.jsonc" ]]
}

# _controller_user_committed <name> — the committed (core-merged) User Profile
# as JSON, or {} for a session-created name. The strict-delta baseline the User
# Editor compares an override against; also the display base before the
# override.
_controller_user_committed() {
  local committed='{}'
  _controller_user_is_committed "$1" \
    && committed="$(profile_loader_load_user "$1" 2>/dev/null || printf '{}')"
  printf '%s' "${committed:-{\}}"
}

# _controller_user_effective <name> — committed profile `*` the install-scoped
# override (userforms file): what the installed user will actually get. Every
# User Editor row displays from this.
_controller_user_effective() {
  local user="$1" committed form='{}'
  committed="$(_controller_user_committed "$user")"
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] \
    && form="$(guided_userform_get "$GUIDED_USERFORMS_FILE" "$user")"
  jq -n --argjson c "$committed" --argjson f "$form" '$c * $f'
}

# _controller_user_field_kind <field> — multi (groups/programs) | text
# (git.name/ git.email) | list (ssh). Drives the userfield screen's render +
# enter.
_controller_user_field_kind() {
  case "$1" in
  groups | programs)              echo multi ;;
  git.name | git.email | ssh.add) echo text ;;
  ssh)                            echo list ;;
  esac
}

# _controller_user_field_options <field> — the candidate lines for a multi
# userfield: a curated group set (matching the create form) or the resolvable
# program names.
_controller_user_field_options() {
  case "$1" in
  groups)   printf '%s\n' wheel docker libvirt kvm ;;
  programs) _controller_user_program_names ;;
  esac
}

# _controller_user_form_set_strict <user> <key> <new-json> <committed-json> —
# set the per-user override at <key>, or DROP it when <new> equals the committed
# value (strict delta: an edit that lands on the committed value leaves no
# override). No-op when no userforms file is wired.
_controller_user_form_set_strict() {
  local user="$1" key="$2" new="$3" committed="$4"
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] || return 0
  if [[ "$(jq -cS . <<<"$new")" == "$(jq -cS . <<<"$committed")" ]]; then
    guided_userform_unset "$GUIDED_USERFORMS_FILE" "$user" "$key"
  else
    guided_userform_set "$GUIDED_USERFORMS_FILE" "$user" "$key" "$new"
  fi
}

# _controller_clone_seed <source> <newname> — copy the source user's effective
# account-shape (shell, sudo, groups, programs) into <newname>'s install-scoped
# delta (ADR 0064). Personal fields (git identity, ssh keys) and the
# password are NOT copied — a clone shares setup, not identity — so the clone
# lands password-less (Proceed stays blocked until set). shell is materialised
# from the resolved full path so a defaulted source shell still copies. No-op
# without a userforms file (non-persistent contexts): the name is still created,
# just without a delta.
_controller_clone_seed() {
  local source_user="$1" new="$2" effective
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] || return 0
  effective="$(_controller_user_effective "$source_user")"
  guided_userform_set "$GUIDED_USERFORMS_FILE" "$new" shell \
    "$(jq -Rn --arg s "$(_controller_user_shell_full "$source_user")" '$s')"
  guided_userform_set "$GUIDED_USERFORMS_FILE" "$new" sudo \
    "$(jq -c 'if .sudo then true else false end' <<<"$effective")"
  guided_userform_set "$GUIDED_USERFORMS_FILE" "$new" groups \
    "$(jq -c '.groups // []' <<<"$effective")"
  guided_userform_set "$GUIDED_USERFORMS_FILE" "$new" programs \
    "$(jq -c '.programs // []' <<<"$effective")"
}

# _controller_user_field_toggle_multi <user> <field> <value> — flip <value> in
# the user's effective array for a multi field, stored as the full override
# (strict delta vs the committed array).
_controller_user_field_toggle_multi() {
  local user="$1" field="$2" value="$3" effective current new committed
  effective="$(_controller_user_effective "$user")"
  current="$(jq -c --arg f "$field" '.[$f] // []' <<<"$effective")"
  new="$(jq -cn --argjson a "$current" --arg v "$value" \
    'if any($a[]; . == $v) then ($a - [$v]) else ($a + [$v]) end')"
  committed="$(jq -c --arg f "$field" '.[$f] // []' \
    <<<"$(_controller_user_committed "$user")")"
  _controller_user_form_set_strict "$user" "$field" "$new" "$committed"
}

# _controller_user_field_set_git <user> <subkey> <value> — set git.name /
# git.email into the user's override git object (strict delta vs the committed
# git). An empty value drops that sub-key.
_controller_user_field_set_git() {
  local user="$1" sub="$2" value="$3" current committed new
  current="$(jq -c '.git // {}' <<<"$(_controller_user_effective "$user")")"
  committed="$(jq -c '.git // {}' <<<"$(_controller_user_committed "$user")")"
  new="$(jq -c --arg k "$sub" --arg v "$value" \
    'if $v == "" then del(.[$k]) else .[$k] = $v end' <<<"$current")"
  _controller_user_form_set_strict "$user" git "$new" "$committed"
}

# _controller_user_field_add_ssh <user> <key> — append one SSH authorized key to
# the user's effective list, stored as the full override (strict delta vs
# committed).
_controller_user_field_add_ssh() {
  local user="$1" key="$2" current committed new
  [[ -n "$key" ]] || return 0
  current="$(jq -c '.ssh_authorized_keys // []' \
    <<<"$(_controller_user_effective "$user")")"
  new="$(jq -c --arg k "$key" '. + [$k]' <<<"$current")"
  committed="$(jq -c '.ssh_authorized_keys // []' \
    <<<"$(_controller_user_committed "$user")")"
  _controller_user_form_set_strict "$user" ssh_authorized_keys "$new" \
    "$committed"
}

# _controller_user_marked <state> <base> — the user toggle list: every committed
# user UNION the currently-selected names (so a just-created name shows), each
# marked [x]/[ ] by membership in the effective .users.
_controller_user_marked() {
  local selected option
  selected="$(jq -c '.users // []' <<<"$(_controller_effective "$1" "$2")")"
  { _controller_user_names; jq -r '.[]' <<<"$selected"; } | awk '!seen[$0]++' \
  | while IFS= read -r option; do
      if jq -ne --argjson s "$selected" --arg o "$option" 'any($s[]; . == $o)' \
          >/dev/null 2>&1; then
        printf '[x] %s\n' "$option"
      else
        printf '[ ] %s\n' "$option"
      fi
    done
}

# _controller_toggle_users <state> <base> <name> — flip <name> in the effective
# .users, written as the FULL override array (replacing the seeded baseline) —
# and never unset, so toggling the last user off truly yields an empty user
# list.
_controller_toggle_users() {
  local state="$1" base="$2" name="$3" current new
  current="$(jq -c '.users // []' \
    <<<"$(_controller_effective "$state" "$base")")"
  new="$(jq -cn --argjson a "$current" --arg v "$name" \
    'if any($a[]; . == $v) then ($a - [$v]) else ($a + [$v]) end')"
  config_state_set "$state" users "$new"
}

# _controller_field_for_label <category> <label> → the dotted path of the row
# whose label matches (reverse lookup through the pure Menu model).
_controller_field_for_label() {
  # Labels render through the Display Label formatter, so reverse-map the
  # formatted label back to a field by formatting each candidate and comparing.
  local cat="$1" want="$2" field label
  while IFS=$'\t' read -r field label; do
    [[ "$(display_label "$label")" == "$want" ]] \
      && { printf '%s' "$field"; return; }
  done < <(menu_category_rows "$cat" "$(_controller_state)" \
    "$(_controller_baseline)" \
    | jq -r '.[] | [.field, .label] | @tsv')
}

# _controller_field_display <path> <state> <base> → the field's menu-displayed
# value (effective value, else its menu default), so the text screen's
# "current:" hint reflects a defaulted field (e.g. 2G) instead of "(unset)".
_controller_field_display() {
  menu_rows "$2" "$3" \
    | jq -r --arg p "$1" 'first(.[] | select(.field == $p) | .value) // ""'
}
