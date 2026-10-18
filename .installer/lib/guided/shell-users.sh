#!/usr/bin/env bash
# =============================================================================
# lib/guided/shell-users.sh — Guided shell users + passwords
# =============================================================================
# Part of the Guided Installer fzf shell (lib/guided/shell.sh, ADR 0039).
#
# Used by: lib/guided/shell.sh (sources it).
# =============================================================================

# =============================================================================
# USERS + PASSWORDS (issue 07)
# =============================================================================
# The host's user list is the ordered union of committed picks (users/*/) and
# ad-hoc creations, committed first, deduped — users[0] is the Primary User
# (positional, ADR 0036). Ad-hoc forms are held aside and materialized into
# users/<name>/profile.jsonc at Proceed; passwords (root + per-user) are held
# aside too and injected via the no-SOPS seam (secrets.sh) — they never
# enter the Config State, so Save/Export never carry them.
_GUIDED_USERS_COMMITTED=()
_GUIDED_ADHOC_ORDER=()
declare -gA _GUIDED_ADHOC_FORM=()
declare -gA _GUIDED_USER_PASSWORDS=()
_GUIDED_ROOT_PASSWORD=""
# The ZFS/LUKS encryption passphrase captured in the menu (ADR 0054). Held aside
# like the passwords — never the Config State — and emitted into the manifest.
_GUIDED_ENCRYPTION_PASSPHRASE=""
# Install-scoped per-user profile deltas from the User Editor (ADR 0051), loaded
# from GUIDED_USERFORMS_FILE before the persistent menu's tmpfiles are reaped.
# Merged onto each user's profile on the install clone at Proceed; never written
# to a committed repo file, never in the Config State. Empty under replay.
_GUIDED_USERFORMS_JSON=""

# _guided_shell_users_reset — clear the per-session Users/password side state.
# No committed user is preselected (ADR 0157): the operator picks or creates
# one, and an install refuses until they do.
_guided_shell_users_reset() {
  _GUIDED_USERS_COMMITTED=()
  _GUIDED_ADHOC_ORDER=()
  declare -gA _GUIDED_ADHOC_FORM=()
  declare -gA _GUIDED_USER_PASSWORDS=()
  _GUIDED_ROOT_PASSWORD=""
  _GUIDED_ENCRYPTION_PASSPHRASE=""
  _GUIDED_USERFORMS_JSON=""
}

# _guided_shell_user_names — committed user names (users/*/ with a
# profile.jsonc), excluding the User Core layer and the users/vm/
# harness-fixtures container (ADR 0035, never installable — its members are
# nested a level down, so the flat glob never enumerates them). The enumerable
# source for the picker.
_guided_shell_user_names() {
  local user_directory name
  for user_directory in "${INSTALLER_DIR}/users"/*/; do
    [[ -d "$user_directory" ]] || continue
    name="${user_directory%/}"
    name="${name##*/}"
    [[ "$name" == "core" || "$name" == "vm" ]] && continue
    [[ -f "${user_directory}profile.jsonc" ]] && printf '%s\n' "$name"
  done
}

# _guided_shell_sync_users — rebuild Config State .users from committed + ad-hoc
# (committed first, order-preserving dedup). Drops the key when no user is set.
_guided_shell_sync_users() {
  local -a all=()
  ((${#_GUIDED_USERS_COMMITTED[@]})) \
    && all+=("${_GUIDED_USERS_COMMITTED[@]}")
  ((${#_GUIDED_ADHOC_ORDER[@]})) && all+=("${_GUIDED_ADHOC_ORDER[@]}")
  _GUIDED_STATE="$(edit_set_users "$_GUIDED_STATE" ${all[@]+"${all[@]}"})"
}

# _guided_shell_pick_users — multi-select committed users into the user list.
# The committed selection replaces any prior committed picks; ad-hoc users
# survive.
_guided_shell_pick_users() {
  local -a names; mapfile -t names < <(_guided_shell_user_names)
  local -a picks=()
  mapfile -t picks < <(_guided_shell_collect_multi users "Users" "${names[@]}")
  ((${#picks[@]})) || return 1
  _GUIDED_USERS_COMMITTED=("${picks[@]}")
  _guided_shell_sync_users
}

# _guided_shell_create_user — the ad-hoc create form: collect a User Profile's
# fields through the seam, author the delta (emit_user_profile prunes empties +
# drops the name), and register the user + its password aside. Password defaults
# to 12345 (the house default) when left blank. rc 1 (no user) on an empty name.
_guided_shell_create_user() {
  local name shell sudo git_name git_email password
  name="$(guided_prompt new_user_name "New user name")"
  [[ -n "$name" ]] || return 1
  shell="$(guided_select new_user_shell "Shell" /bin/bash /bin/zsh /bin/fish)"
  # Default sudo ON (→ wheel), unifying with the persistent-menu create + the
  # materialize fallback (ADR 0051): the first option is the default under
  # replay.
  sudo="$(guided_select new_user_sudo "Sudo (→ wheel)" true false)"
  local -a groups programs ssh_keys
  mapfile -t groups < <(_guided_shell_collect_multi new_user_groups "Groups" \
    wheel docker libvirt kvm)
  local -a program_names
  mapfile -t program_names < <(_guided_shell_program_names)
  mapfile -t programs < <(_guided_shell_collect_multi new_user_programs \
    "Programs" \
    "${program_names[@]}")
  # ADR 0134: bareness (drop User Core's programs wholesale) + config_exclude
  # (install a program's package but skip its config). Inherit defaults ON (the
  # first option under replay), config_exclude offers the user's own programs.
  local inherit
  inherit="$(guided_select new_user_programs_inherit \
    "Inherit User Core programs" true false)"
  # config_exclude offers ALL program names, not just the ones selected above:
  # a user also gets User Core's programs (kitty, zsh, …), and their config is
  # just as skippable (ADR 0134).
  local -a config_excluded
  mapfile -t config_excluded < <(_guided_shell_collect_multi \
    new_user_config_exclude \
    "Skip config for (config_exclude)" "${program_names[@]}")
  git_name="$(guided_prompt new_user_git_name "Git name")"
  git_email="$(guided_prompt new_user_git_email "Git email")"
  mapfile -t ssh_keys < <(_guided_shell_collect_multi new_user_ssh_keys \
    "SSH authorized keys")
  password="$(guided_prompt new_user_password "Password (default 12345)")"
  [[ -n "$password" ]] || password="12345"

  local form; form="$(_guided_shell_user_form)"
  local profile; profile="$(emit_user_profile "$form")"
  # programs_inherit:false is the meaningful flag but the pruner drops `false`;
  # re-attach it explicitly when bareness was chosen (true is the omitted
  # default). See ADR 0134.
  [[ "$inherit" == "false" ]] \
    && profile="$(jq -c '. + {programs_inherit:false}' <<<"$profile")"
  _GUIDED_ADHOC_FORM["$name"]="$profile"
  _GUIDED_ADHOC_ORDER+=("$name")
  _GUIDED_USER_PASSWORDS["$name"]="$password"
  _guided_shell_sync_users
}

# _guided_shell_user_form — the create form as User Profile JSON, from the
# caller's collected fields (dynamic scope).
_guided_shell_user_form() {
  jq -n \
    --arg shell "$shell" \
    --argjson sudo "$([[ "$sudo" == "true" ]] && echo true || echo false)" \
    --argjson groups "$(_emit_json_array "${groups[@]}")" \
    --argjson programs "$(_emit_json_array "${programs[@]}")" \
    --argjson config_exclude "$(_emit_json_array \
      "${config_excluded[@]+"${config_excluded[@]}"}")" \
    --arg gn "$git_name" --arg ge "$git_email" \
    --argjson keys "$(_emit_json_array "${ssh_keys[@]}")" \
    '{shell:$shell, sudo:$sudo, groups:$groups, programs:$programs,
      config_exclude:$config_exclude,
      git: ({name:$gn, email:$ge} | with_entries(select(.value != ""))),
      ssh_authorized_keys:$keys}'
}

# The committed user names snapshotted at the start of materialize (before any
# ad-hoc/default profile is written), so the userform merge can tell a repo user
# from a session-created one. Space-padded for word-boundary membership tests.
_GUIDED_COMMITTED_AT_START=""

# _guided_shell_materialize_users [mode] — write each ad-hoc User Profile delta
# to users/<name>/profile.jsonc so the back-end Runner can load it. At Proceed
# this is a transient write to the live clone; Save (issue 08) commits the same
# file. mode is "proceed" (default) or "save": under Save the install-scoped
# User Editor deltas are NOT merged onto a committed profile (that would rewrite
# committed source — ADR 0051); the caller warns about the dropped edits
# instead.
_guided_shell_materialize_users() {
  local mode="${1:-proceed}" name user_directory
  _GUIDED_COMMITTED_AT_START=" $(_guided_shell_user_names \
    | awk '{ printf "%s ", $0 }')"
  for name in "${_GUIDED_ADHOC_ORDER[@]+"${_GUIDED_ADHOC_ORDER[@]}"}"; do
    user_directory="${INSTALLER_DIR}/users/${name}"
    mkdir -p "$user_directory"
    printf '%s\n' "${_GUIDED_ADHOC_FORM[$name]}" \
      > "${user_directory}/profile.jsonc"
  done
  # Persistent-path created users carry only a name in the Config State; give
  # any
  # effective user lacking a committed profile a sensible default (bash + wheel
  # sudo). Committed/legacy-ad-hoc users already have one and are skipped.
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    user_directory="${INSTALLER_DIR}/users/${name}"
    [[ -f "${user_directory}/profile.jsonc" ]] && continue
    mkdir -p "$user_directory"
    emit_user_profile \
      '{"shell":"/bin/bash","sudo":true,"groups":["wheel"],
        "programs":["searxng"]}' \
      > "${user_directory}/profile.jsonc"
  done < <(jq -r '(.users // [])[]' <<<"$(_guided_shell_effective)")

  # Install-scoped User Editor deltas (ADR 0051): merge each held-aside per-user
  # delta onto that user's profile ON THE CLONE — the committed source in the
  # repo
  # is only touched here because INSTALLER_DIR is the transient install clone at
  # Proceed.
  # A committed user's profile stays a delta over User Core (its existing delta
  # `*` the edit); an ad-hoc user's just-written profile gets the edit on top.
  _guided_shell_apply_userforms "$mode"
}

# _guided_shell_apply_userforms [mode] — merge _GUIDED_USERFORMS_JSON deltas
# onto each named user's profile.jsonc (the clone). No-op when empty (replay /
# no edits). Reads the existing profile via _program_registry_parse (JSONC→JSON)
# so committed comments are tolerated; writes plain JSON (comments are not
# needed on the clone). Under mode "save" a user that was committed at the start
# of materialize is SKIPPED — Save never rewrites committed source (ADR 0051).
_guided_shell_apply_userforms() {
  local mode="${1:-proceed}" name delta directory profile_file base
  [[ -n "${_GUIDED_USERFORMS_JSON:-}" ]] || return 0
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if [[ "$mode" == "save" \
       && "$_GUIDED_COMMITTED_AT_START" == *" $name "* ]]; then
      continue
    fi
    delta="$(jq -c --arg n "$name" '.[$n] // {}' <<<"$_GUIDED_USERFORMS_JSON")"
    [[ "$delta" == "{}" || -z "$delta" ]] && continue
    directory="${INSTALLER_DIR}/users/${name}"
    profile_file="${directory}/profile.jsonc"
    mkdir -p "$directory"
    base='{}'
    if [[ -f "$profile_file" ]]; then
      base="$(_program_registry_parse "$profile_file")"
    fi
    jq -n --argjson b "$base" --argjson d "$delta" '$b * $d' > "$profile_file"
  done < <(jq -r 'keys[]' <<<"$_GUIDED_USERFORMS_JSON")
}

# _guided_shell_committed_userform_edits — the committed users carrying an
# install-only User Editor delta (ADR 0051 Save-warn), one per line.
# "Committed" = has a repo users/<name>/profile.jsonc; run BEFORE materialize
# (which writes ad-hoc profiles), so an ad-hoc name has no file yet and is not
# reported. Pure: reads the held-aside deltas + the filesystem.
_guided_shell_committed_userform_edits() {
  [[ -n "${_GUIDED_USERFORMS_JSON:-}" ]] || return 0
  local user
  while IFS= read -r user; do
    [[ -n "$user" ]] || continue
    [[ -f "${INSTALLER_DIR}/users/${user}/profile.jsonc" ]] \
      && printf '%s\n' "$user"
  done < <(jq -r 'keys[]' <<<"$_GUIDED_USERFORMS_JSON")
}

# Credentials are captured in the menu (ticket 03) — the persistent-fzf
# front-end writes GUIDED_SECRETS_FILE and guided_run_persistent loads it into
# the held-aside vars via _guided_shell_load_secrets_file. There is no post-menu
# prompt.

# _guided_shell_finalize_users — Proceed-time user side effects: materialize
# ad-hoc profiles and, when the install flow set GUIDED_SECRETS_MANIFEST, write
# the no-SOPS password manifest there for 03-install.sh to persist into
# install-state (the file the chroot/Runner resolve via .guided_passwords.*).
# Passwords thus reach the back-end without ever touching the Effective Config.
_guided_shell_finalize_users() {
  _guided_shell_materialize_users
  [[ -n "${GUIDED_SECRETS_MANIFEST:-}" ]] \
    && _guided_shell_secrets_manifest >"$GUIDED_SECRETS_MANIFEST"
  return 0
}

# _guided_shell_set_root_password — hold the root password aside (never the
# Config State, so Save/Export never carry it). rc 1 (unchanged) on empty input.
_guided_shell_set_root_password() {
  local password; password="$(guided_prompt root_password "Root password")"
  [[ -n "$password" ]] || return 1
  _GUIDED_ROOT_PASSWORD="$password"
}

# _guided_shell_secrets_manifest — the no-SOPS password manifest
# guided_write_passwords consumes: { root_password?, enc_passphrase?, users?: {
# <name>:{password} } }. Built from the held-aside root + per-user passwords +
# encryption passphrase; empty {} when nothing is set. The passphrase is read
# pre-chroot by zfs_collect_encryption_passphrase (ADR 0054), the rest staged
# into install-state. Pure: reads the side state, emits JSON.
_guided_shell_secrets_manifest() {
  local manifest='{}' name
  [[ -n "$_GUIDED_ROOT_PASSWORD" ]] \
    && manifest="$(jq --arg pw "$_GUIDED_ROOT_PASSWORD" \
    '.root_password = $pw' <<<"$manifest")"
  [[ -n "$_GUIDED_ENCRYPTION_PASSPHRASE" ]] && manifest="$(jq \
    --arg pw "$_GUIDED_ENCRYPTION_PASSPHRASE" '.enc_passphrase = $pw' \
    <<<"$manifest")"
  for name in "${!_GUIDED_USER_PASSWORDS[@]}"; do
    manifest="$(jq --arg n "$name" --arg pw "${_GUIDED_USER_PASSWORDS[$name]}" \
      '.users[$n] = {password: $pw}' <<<"$manifest")"
  done
  # Default posture (ADR 0055): fill any secret the operator left unset with
  # 12345 — root, every effective user, and (when encryption is on) the
  # passphrase — so Proceed never needed a password. Held-aside overrides above
  # already won; this only backfills the gaps.
  local effective_json users encryption
  effective_json="$(_guided_shell_effective)"
  users="$(jq -c '.users // []' <<<"$effective_json")"
  [[ "$(config_state_get "$effective_json" options.encryption)" == "true" ]] \
    && encryption=true || encryption=false
  guided_default_missing_secrets "$manifest" "$users" "$encryption"
}
