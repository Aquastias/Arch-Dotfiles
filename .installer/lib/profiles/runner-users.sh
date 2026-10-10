#!/usr/bin/env bash
# =============================================================================
# lib/profiles/runner-users.sh — the Runner's user accounts
# =============================================================================
# Used by: lib/profiles/runner.sh (sources it). Creates each user (Primary
# User display name, secrets-sourced passwords), their groups, authorized keys,
# and the temporary sudo grant the AUR pass needs.
# =============================================================================

_runner_users_resolve_secrets() {
  local name="$1"
  local host_state="${MOUNT_ROOT}/install-state.json"
  [[ -f "$host_state" ]] || return 0
  local raw_path
  # The .secrets / .guided_passwords precedence lives in the Install State
  # module — the schema's owner — not re-encoded here.
  raw_path="$(install_state_credential_path "$host_state" user "$name")"
  [[ -n "$raw_path" && -f "$raw_path" ]] || return 0
  local chroot_directory="${MOUNT_ROOT}${_RUNNER_RUNTIME_DIR}/secrets"
  mkdir -p "$chroot_directory"
  cp "$raw_path" "${chroot_directory}/${name}-secrets.json"
  printf '%s' "${_RUNNER_RUNTIME_DIR}/secrets/${name}-secrets.json"
}

runner_create_user() {
  local name="$1" json="$2" fullname="${3:-}"
  local shell sudo_flag groups_csv
  shell="$(printf '%s' "$json" | jq -r '.shell // "/bin/bash"')"
  sudo_flag="$(printf '%s' "$json" | jq -r '.sudo // false')"
  groups_csv="$(runner_resolve_user_groups "$json")"
  info "Creating user: ${name}" \
       "(shell=${shell}, sudo=${sudo_flag}, groups=${groups_csv:-<none>})"
  local secret_path
  secret_path="$(_runner_users_resolve_secrets "$name")"
  # Primary User display name → GECOS (ADR 0121). Passed as a chroot env var
  # (arch-chroot strips the host env, and adding a positional arg would collide
  # with the optional secrets path); create-user.sh reads USER_FULLNAME. An
  # array so a name with spaces stays one token; empty ⇒ no env prefix.
  local -a env_pfx=()
  [[ -n "$fullname" ]] && env_pfx=(env "USER_FULLNAME=$fullname")
  arch-chroot "$MOUNT_ROOT" "${env_pfx[@]}" \
    /usr/bin/bash /root/lib-chroot/create-user.sh \
    "$name" "$shell" "$groups_csv" "$_RUNNER_DEFAULT_PASSWORD" \
    ${secret_path:+"$secret_path"}
}

# Re-apply the full group list for a user. Run after all programs are installed
# so package-created groups (docker, libvirt, kvm, …) now exist in the chroot.
runner_apply_user_groups() {
  local name="$1" json="$2"
  local groups_csv
  groups_csv="$(runner_resolve_user_groups "$json")"
  [[ -z "$groups_csv" ]] && return 0
  info "Reconciling groups for user: ${name}  (groups=${groups_csv})"
  arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- \
    "$name" "$groups_csv" <<'CHROOT_GROUPS'
set -e
NAME="$1"; GROUPS_CSV="$2"
IFS=',' read -ra _ALL <<< "$GROUPS_CSV"
existing=""
for g in "${_ALL[@]}"; do
  [[ -z "$g" ]] && continue
  if getent group "$g" >/dev/null 2>&1; then
    existing+="${g},"
  else
    echo "  [reconcile] group '${g}' still absent after install — skipping" >&2
  fi
done
existing="${existing%,}"
[[ -z "$existing" ]] && exit 0
usermod -aG "$existing" "$NAME"
CHROOT_GROUPS
}

# Temporarily grant NOPASSWD sudo to a user. Required for paru/makepkg to
# install built packages via pacman during the chroot install.
runner_grant_temporary_sudo() {
  local user="$1"
  printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$user" \
    >"${MOUNT_ROOT}${_RUNNER_SUDO_DROPIN}"
  chmod 440 "${MOUNT_ROOT}${_RUNNER_SUDO_DROPIN}"
}

runner_revoke_temporary_sudo() {
  rm -f "${MOUNT_ROOT}${_RUNNER_SUDO_DROPIN}"
}

_runner_users_write_authorized_keys() {
  local user="$1" json="$2"
  local -a keys=()
  mapfile -t keys < <(printf '%s' "$json" \
    | jq -r '.ssh_authorized_keys[]?' 2>/dev/null)
  ((${#keys[@]} > 0)) || return 0
  info "Writing authorized_keys for user: ${user}  (${#keys[@]} key(s))"
  # Pass keys as positional args, not via a host ${MOUNT_ROOT}/tmp staging file:
  # on a ZFS install /tmp is its own dataset (rpool/tmp), and the host can write
  # the staging file to the root-dataset dir *before* that dataset mounts over
  # it — the chroot then sees the freshly-mounted empty /tmp and the copy fails
  # "cannot stat". Args cross the chroot boundary with no shared-path
  # assumption.
  arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- "$user" "${keys[@]}" \
    <<'CHROOT_AUTHKEYS'
set -e
USER_NAME="$1"; shift
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
mkdir -p "${HOME_DIR}/.ssh"
chmod 700 "${HOME_DIR}/.ssh"
printf '%s\n' "$@" > "${HOME_DIR}/.ssh/authorized_keys"
chmod 600 "${HOME_DIR}/.ssh/authorized_keys"
chown -R "${USER_NAME}:${USER_NAME}" "${HOME_DIR}/.ssh"
CHROOT_AUTHKEYS
}

# The Primary User (first in the list) gets the display name; the rest do not
# (ADR 0121 — avatar/name is scoped to the Primary User).
# Reads runner_run_profiles' users (dynamic scope).
# shellcheck disable=SC2154
runner_create_users() {
  local primary_fullname user index=0
  primary_fullname="$(install_config_fullname)"
  for user in "${users[@]}"; do
    if [[ $index -eq 0 ]]; then
      runner_create_user "$user" "${USER_JSONS[$user]}" "$primary_fullname"
    else
      runner_create_user "$user" "${USER_JSONS[$user]}"
    fi
    _runner_users_write_authorized_keys "$user" "${USER_JSONS[$user]}"
    index=$((index + 1))
  done
}

