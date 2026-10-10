#!/usr/bin/env bash
# =============================================================================
# lib/profiles/runner-services.sh — the Runner's unit enabling
# =============================================================================
# Used by: lib/profiles/runner.sh (sources it). Enables Host
# Program system units and each user's program + profile user units.
# =============================================================================

runner_enable_system_services() {
  local program="$1"
  local relative_path config_file
  relative_path="$(resolve_program "$program")"
  config_file="${INSTALLER_DIR}/programs/${relative_path}/config.jsonc"
  local -a services=()
  mapfile -t services < <(jsonc_strip "$config_file" \
    | jq -r '.system_services[]?' 2>/dev/null)
  ((${#services[@]} > 0)) || return 0
  local service
  for service in "${services[@]}"; do
    info "Enabling system service: ${service}"
    arch-chroot "$MOUNT_ROOT" systemctl enable "$service"
  done
}

runner_enable_user_services() {
  local user="$1" program="$2"
  local relative_path config_file
  relative_path="$(resolve_program "$program")"
  config_file="${INSTALLER_DIR}/programs/${relative_path}/config.jsonc"
  local -a services=()
  mapfile -t services < <(jsonc_strip "$config_file" \
    | jq -r '.user_services[]?' 2>/dev/null)
  ((${#services[@]} > 0)) || return 0
  local service
  for service in "${services[@]}"; do
    info "Enabling user service: ${service}  (user=${user})"
    arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- \
      "$user" "$service" <<'CHROOT_USERSVC'
set -e
USER_NAME="$1"; SVC="$2"
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
SVC_DIR="${HOME_DIR}/.config/systemd/user/default.target.wants"
mkdir -p "$SVC_DIR"
SVC_FILE="$(find /usr/lib/systemd/user /usr/local/lib/systemd/user \
  -name "${SVC}.service" 2>/dev/null | head -1)"
if [[ -z "$SVC_FILE" ]]; then
  echo "  [user-service] ${SVC}.service not found — skipping" >&2
  exit 0
fi
ln -sf "$SVC_FILE" "${SVC_DIR}/${SVC}.service"
chown -R "${USER_NAME}:${USER_NAME}" "${HOME_DIR}/.config/systemd"
CHROOT_USERSVC
  done
}

# _runner_services_resolve_user_unit <svc> <search_dir...>
# Echo the path to <svc>.service found in the given roots, or return 1 (no
# output) when absent. Pure: searches the given dirs only.
_runner_services_resolve_user_unit() {
  local service="$1"; shift
  local unit_file
  unit_file="$(find "$@" -name "${service}.service" -print -quit 2>/dev/null)"
  [[ -n "$unit_file" ]] || return 1
  printf '%s\n' "$unit_file"
}

# runner_enable_profile_user_services <user> <user_json>
# Enable a user profile's user_services[] — the offline equivalent of
# `systemctl --user enable`: a symlink into the user's
# default.target.wants. Runs after the user's programs + dotfiles are placed.
# A listed unit that isn't installed aborts with an actionable message (the
# per-program list, by contrast, skips a missing unit).
runner_enable_profile_user_services() {
  local user="$1" json="$2"
  local -a services=()
  mapfile -t services < <(printf '%s' "$json" | jq -r '.user_services[]?')
  ((${#services[@]} > 0)) || return 0
  local service
  for service in "${services[@]}"; do
    if ! _runner_services_resolve_user_unit "$service" \
         "${MOUNT_ROOT}/usr/lib/systemd/user" \
         "${MOUNT_ROOT}/usr/local/lib/systemd/user" \
         "${MOUNT_ROOT}/etc/systemd/user" >/dev/null; then
      error "User '${user}' lists user_service '${service}', but no" \
            "${service}.service unit is installed. Declare the program that" \
            "provides it before this entry, or fix the name."
      return 1
    fi
    info "Enabling user service: ${service}  (user=${user})"
    arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- \
      "$user" "$service" <<'CHROOT_PROFILE_USERSVC'
set -e
USER_NAME="$1"; SVC="$2"
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
SVC_DIR="${HOME_DIR}/.config/systemd/user/default.target.wants"
mkdir -p "$SVC_DIR"
SVC_FILE="$(find /usr/lib/systemd/user /usr/local/lib/systemd/user \
  /etc/systemd/user -name "${SVC}.service" 2>/dev/null | head -1)"
ln -sf "$SVC_FILE" "${SVC_DIR}/${SVC}.service"
chown -R "${USER_NAME}:${USER_NAME}" "${HOME_DIR}/.config/systemd"
CHROOT_PROFILE_USERSVC
  done
}

