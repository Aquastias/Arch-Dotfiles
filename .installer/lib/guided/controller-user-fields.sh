#!/usr/bin/env bash
# =============================================================================
# lib/guided/controller-user-fields.sh — user + root fields, sysctl lines, labels
# =============================================================================
# Part of the guided controller (lib/guided/controller.sh, ADR 0042).
#
# Used by: lib/guided/controller.sh (sources it).
# =============================================================================

# _controller_sysctl_lines <state> <base> → the current sysctl pairs ("key=value"), one
# per line, from the effective view (so the seeded vm.swappiness=10 shows up).
_controller_sysctl_lines() {
  jq -r '(.sysctl // {}) | to_entries[] | "\(.key)=\(.value)"' \
    <<<"$(_controller_effective "$1" "$2")"
}

# _controller_user_names → committed user names (users/<name>/profile.jsonc, minus
# core and the `vm-*` harness fixtures — ADR 0035 throwaway smoke-test users
# have no place in an operator's menu, mirroring profiles_list's core/vm skip).
_controller_user_names() {
  local d n
  for d in "${INSTALLER_DIR:-.}"/users/*/; do
    [[ -d "$d" ]] || continue
    n="$(basename "$d")"
    [[ "$n" == "core" || "$n" == vm-* ]] && continue
    [[ -f "${d}profile.jsonc" ]] && printf '%s\n' "$n"
  done
}

# _controller_default_user_shell — the login shell an ad-hoc user gets: User Core's
# declared shell, else /bin/zsh. Reading User Core rather than hardcoding keeps
# the guided default in step with the committed base (ADR 0056 curation), so a
# name typed into the menu lands in the same shell a declared user would.
_controller_default_user_shell() {
  local s=""
  [[ -n "${INSTALLER_DIR:-}" && -f "${INSTALLER_DIR}/users/core/profile.jsonc" ]] \
    && s="$(_program_registry_parse "${INSTALLER_DIR}/users/core/profile.jsonc" 2>/dev/null \
          | jq -r '.shell // empty' 2>/dev/null)"
  printf '%s' "${s:-/bin/zsh}"
}

# _controller_user_shell_full <name> — the effective login shell PATH: the User
# Editor's
# install-scoped override (userforms file) if set, else the committed User
# Profile's shell merged over User Core, else the User Core default (an ad-hoc
# name with no committed profile). The single source of truth the list display,
# the editor row, and the shell cycle all read.
_controller_user_shell_full() {
  local n="$1" s=""
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] \
    && s="$(guided_userform_field "$GUIDED_USERFORMS_FILE" "$n" shell)"
  if [[ -z "$s" && -n "${INSTALLER_DIR:-}" \
     && -f "${INSTALLER_DIR}/users/${n}/profile.jsonc" ]]; then
    s="$(profile_loader_load_user "$n" 2>/dev/null \
      | jq -r '.shell // empty' 2>/dev/null)"
  fi
  [[ -n "$s" ]] || s="$(_controller_default_user_shell)"
  printf '%s' "$s"
}

# _controller_user_shell <name> — the short login shell (basename) for the list row.
_controller_user_shell() {
  local s; s="$(_controller_user_shell_full "$1")"
  printf '%s' "${s##*/}"
}

# _controller_root_shell_full — root's effective login shell PATH (ADR 0054): the
# Config State override (options.root_shell) merged over the baseline, else the
# baseline's, else /bin/bash. The single source the Users row + the cycle read.
_controller_root_shell_full() {
  local s
  s="$(jq -r '.options.root_shell // "/bin/bash"' \
    <<<"$(_controller_effective "$(_controller_state)" "$(_controller_baseline)")")"
  printf '%s' "$s"
}

# _controller_root_shell — root's short login shell (basename) for the Users row.
_controller_root_shell() {
  local s; s="$(_controller_root_shell_full)"; printf '%s' "${s##*/}"
}

# _controller_root_shell_committed — the baseline (launch-state) root shell, or
# /bin/bash. The strict-delta reference: cycling onto it drops the override.
_controller_root_shell_committed() {
  jq -r '.options.root_shell // "/bin/bash"' <<<"$(_controller_baseline)"
}

# _controller_user_is_committed <name> — rc 0 when the user has a committed profile
# (users/<name>/profile.jsonc under INSTALLER_DIR): the editor shows `enabled`
# for
# those
# and `✗ remove user` for a session-created (ad-hoc) name instead.
_controller_user_is_committed() {
  [[ -n "${INSTALLER_DIR:-}" && -f "${INSTALLER_DIR}/users/${1}/profile.jsonc" ]]
}

# _controller_user_committed <name> — the committed (core-merged) User Profile as JSON,
# or {} for a session-created name. The strict-delta baseline the User Editor
# compares an override against; also the display base before the override.
_controller_user_committed() {
  local c='{}'
  _controller_user_is_committed "$1" \
    && c="$(profile_loader_load_user "$1" 2>/dev/null || printf '{}')"
  printf '%s' "${c:-{\}}"
}

# _controller_user_effective <name> — committed profile `*` the install-scoped override
# (userforms file): what the installed user will actually get. Every User Editor
# row displays from this.
_controller_user_effective() {
  local n="$1" c f='{}'
  c="$(_controller_user_committed "$n")"
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] \
    && f="$(guided_userform_get "$GUIDED_USERFORMS_FILE" "$n")"
  jq -n --argjson c "$c" --argjson f "$f" '$c * $f'
}

# _controller_user_field_kind <field> — multi (groups/programs) | text (git.name/
# git.email) | list (ssh). Drives the userfield screen's render + enter.
_controller_user_field_kind() {
  case "$1" in
  groups | programs)              echo multi ;;
  git.name | git.email | ssh.add) echo text ;;
  ssh)                            echo list ;;
  esac
}

# _controller_user_field_options <field> — the candidate lines for a multi userfield: a
# curated group set (matching the create form) or the resolvable program names.
_controller_user_field_options() {
  case "$1" in
  groups)   printf '%s\n' wheel docker libvirt kvm ;;
  programs) _controller_user_program_names ;;
  esac
}

# _controller_user_form_set_strict <user> <key> <new-json> <committed-json> — set the
# per-user override at <key>, or DROP it when <new> equals the committed value
# (strict delta: an edit that lands on the committed value leaves no override).
# No-op when no userforms file is wired.
_controller_user_form_set_strict() {
  local u="$1" k="$2" new="$3" committed="$4"
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] || return 0
  if [[ "$(jq -cS . <<<"$new")" == "$(jq -cS . <<<"$committed")" ]]; then
    guided_userform_unset "$GUIDED_USERFORMS_FILE" "$u" "$k"
  else
    guided_userform_set "$GUIDED_USERFORMS_FILE" "$u" "$k" "$new"
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
  local src="$1" new="$2" eff
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] || return 0
  eff="$(_controller_user_effective "$src")"
  guided_userform_set "$GUIDED_USERFORMS_FILE" "$new" shell \
    "$(jq -Rn --arg s "$(_controller_user_shell_full "$src")" '$s')"
  guided_userform_set "$GUIDED_USERFORMS_FILE" "$new" sudo \
    "$(jq -c 'if .sudo then true else false end' <<<"$eff")"
  guided_userform_set "$GUIDED_USERFORMS_FILE" "$new" groups \
    "$(jq -c '.groups // []' <<<"$eff")"
  guided_userform_set "$GUIDED_USERFORMS_FILE" "$new" programs \
    "$(jq -c '.programs // []' <<<"$eff")"
}

# _controller_user_field_toggle_multi <user> <field> <value> — flip <value> in the
# user's
# effective array for a multi field, stored as the full override (strict delta
# vs
# the committed array).
_controller_user_field_toggle_multi() {
  local u="$1" field="$2" val="$3" eff cur new committed
  eff="$(_controller_user_effective "$u")"
  cur="$(jq -c --arg f "$field" '.[$f] // []' <<<"$eff")"
  new="$(jq -cn --argjson a "$cur" --arg v "$val" \
    'if any($a[]; . == $v) then ($a - [$v]) else ($a + [$v]) end')"
  committed="$(jq -c --arg f "$field" '.[$f] // []' \
    <<<"$(_controller_user_committed "$u")")"
  _controller_user_form_set_strict "$u" "$field" "$new" "$committed"
}

# _controller_user_field_set_git <user> <subkey> <value> — set git.name / git.email into
# the user's override git object (strict delta vs the committed git). An empty
# value drops that sub-key.
_controller_user_field_set_git() {
  local u="$1" sub="$2" val="$3" cur committed new
  cur="$(jq -c '.git // {}' <<<"$(_controller_user_effective "$u")")"
  committed="$(jq -c '.git // {}' <<<"$(_controller_user_committed "$u")")"
  new="$(jq -c --arg k "$sub" --arg v "$val" \
    'if $v == "" then del(.[$k]) else .[$k] = $v end' <<<"$cur")"
  _controller_user_form_set_strict "$u" git "$new" "$committed"
}

# _controller_user_field_add_ssh <user> <key> — append one SSH authorized key to the
# user's effective list, stored as the full override (strict delta vs
# committed).
_controller_user_field_add_ssh() {
  local u="$1" key="$2" cur committed new
  [[ -n "$key" ]] || return 0
  cur="$(jq -c '.ssh_authorized_keys // []' <<<"$(_controller_user_effective "$u")")"
  new="$(jq -c --arg k "$key" '. + [$k]' <<<"$cur")"
  committed="$(jq -c '.ssh_authorized_keys // []' \
    <<<"$(_controller_user_committed "$u")")"
  _controller_user_form_set_strict "$u" ssh_authorized_keys "$new" "$committed"
}

# _controller_user_marked <state> <base> — the user toggle list: every committed user
# UNION the currently-selected names (so a just-created name shows), each marked
# [x]/[ ] by membership in the effective .users.
_controller_user_marked() {
  local sel opt; sel="$(jq -c '.users // []' <<<"$(_controller_effective "$1" "$2")")"
  { _controller_user_names; jq -r '.[]' <<<"$sel"; } | awk '!seen[$0]++' \
  | while IFS= read -r opt; do
      if jq -ne --argjson s "$sel" --arg o "$opt" 'any($s[]; . == $o)' \
          >/dev/null 2>&1; then
        printf '[x] %s\n' "$opt"
      else
        printf '[ ] %s\n' "$opt"
      fi
    done
}

# _controller_toggle_users <state> <base> <name> — flip <name> in the effective .users,
# written as the FULL override array (replacing the seeded baseline) — and never
# unset, so toggling the last user off truly yields an empty user list.
_controller_toggle_users() {
  local state="$1" base="$2" name="$3" cur new
  cur="$(jq -c '.users // []' <<<"$(_controller_effective "$state" "$base")")"
  new="$(jq -cn --argjson a "$cur" --arg v "$name" \
    'if any($a[]; . == $v) then ($a - [$v]) else ($a + [$v]) end')"
  config_state_set "$state" users "$new"
}

# _controller_field_for_label <category> <label> → the dotted path of the row whose
# label matches (reverse lookup through the pure Menu model).
_controller_field_for_label() {
  # Labels render through the Display Label formatter, so reverse-map the
  # formatted label back to a field by formatting each candidate and comparing.
  local cat="$1" want="$2" field label
  while IFS=$'\t' read -r field label; do
    [[ "$(display_label "$label")" == "$want" ]] \
      && { printf '%s' "$field"; return; }
  done < <(menu_category_rows "$cat" "$(_controller_state)" "$(_controller_baseline)" \
    | jq -r '.[] | [.field, .label] | @tsv')
}

# _controller_field_display <path> <state> <base> → the field's menu-displayed value
# (effective value, else its menu default), so the text screen's "current:" hint
# reflects a defaulted field (e.g. 2G) instead of "(unset)".
_controller_field_display() {
  menu_rows "$2" "$3" \
    | jq -r --arg p "$1" 'first(.[] | select(.field == $p) | .value) // ""'
}
