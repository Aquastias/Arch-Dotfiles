#!/usr/bin/env bash
# =============================================================================
# lib/profiles.sh — Host/user profile runner
# =============================================================================
# Sourced by 03-install.sh after configure_system().
# Requires: lib/common.sh and lib/configs.sh already sourced.
#
# Public API:
#   run_profiles  Entry point. Reads merged host config for $RESOLVED_HOSTNAME,
#                 creates users, installs system programs, bootstraps paru per
#                 user, installs user programs, then cleans up the staged tree.
#
# Behaviour for missing pieces:
#   - Hosts/users core config missing → warn and return (graceful).
#   - Specific host config missing    → warn and return (graceful).
#   - User dir referenced but missing → hard error.
#   - Program not found               → hard error.
#   - System flag mismatch            → hard error.
#
# Exports inside arch-chroot for each program install.sh:
#   OS_DIR, PROGRAMS, SHELL_COMMONS
# =============================================================================

readonly _PROFILES_DEFAULT_PASSWORD="12345"
readonly _PROFILES_RUNTIME_DIR="/root/.os-runtime"
readonly _PROFILES_SUDO_DROPIN="/etc/sudoers.d/01-profiles-runner"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Resolve a program name to its "category/name" relative path under programs/.
# Echoes the relative path on stdout. Returns 1 if not found.
_profiles_resolve_program() {
  local name="$1"
  local d cat
  for d in "${OS_DIR}/programs"/*/"$name"; do
    [[ -d "$d" ]] || continue
    cat="$(basename "$(dirname "$d")")"
    printf '%s/%s\n' "$cat" "$name"
    return 0
  done
  return 1
}

# Validate a list of program names against an expected `system` flag.
# $1 = "true" or "false". Remaining args = program names.
_profiles_validate_programs() {
  local expected="$1"
  shift
  local prog rel dir is_sys
  for prog in "$@"; do
    rel="$(_profiles_resolve_program "$prog")" ||
      error "Program '${prog}' not found under ${OS_DIR}/programs/<cat>/${prog}/."
    dir="${OS_DIR}/programs/${rel}"
    [[ -f "$dir/config.jsonc" ]] || error "Program '${prog}' missing config.jsonc at ${dir}/"
    [[ -f "$dir/install.sh" ]] || error "Program '${prog}' missing install.sh at ${dir}/"
    is_sys="$(_configs_parse "$dir/config.jsonc" | jq -r '.system')"
    if [[ "$is_sys" != "$expected" ]]; then
      if [[ "$expected" == "true" ]]; then
        error "Program '${prog}' is referenced from a host config but its config.jsonc has system=${is_sys}. Expected true."
      else
        error "Program '${prog}' is referenced from a user config but its config.jsonc has system=${is_sys}. Expected false."
      fi
    fi
  done
}

# Stage program tree + shell-stdlib.sh inside the chroot so install.sh scripts
# can run via arch-chroot with stable, predictable paths.
_profiles_stage_runtime() {
  local target="${MOUNT_ROOT}${_PROFILES_RUNTIME_DIR}"
  rm -rf "$target"
  mkdir -p "$target/lib"
  if [[ -d "${OS_DIR}/programs" ]]; then
    cp -r "${OS_DIR}/programs" "$target/programs"
  else
    mkdir -p "$target/programs"
  fi
  cp "${OS_DIR}/lib/shell-stdlib.sh" "$target/lib/shell-stdlib.sh"
  find "$target/programs" -name '*.sh' -exec chmod +x {} \;
}

# Remove the staged runtime tree and any leftover sudoers drop-ins.
# Idempotent — safe to call from finalize and from error traps.
_profiles_cleanup() {
  rm -rf "${MOUNT_ROOT}${_PROFILES_RUNTIME_DIR}"
  rm -f "${MOUNT_ROOT}${_PROFILES_SUDO_DROPIN}"
}

_profiles_create_user() {
  local name="$1" json="$2"
  local shell sudo_flag groups_csv
  shell="$(printf '%s' "$json" | jq -r '.shell // "/bin/bash"')"
  sudo_flag="$(printf '%s' "$json" | jq -r '.sudo // false')"
  groups_csv="$(printf '%s' "$json" | jq -r '
    (.groups // []) +
    (if .sudo == true and ((.groups // []) | index("wheel") == null)
      then ["wheel"] else [] end)
    | unique_by(.) | join(",")
  ')"

  info "Creating user: ${name}  (shell=${shell}, sudo=${sudo_flag}, groups=${groups_csv:-<none>})"

  arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- \
    "$name" "$shell" "$groups_csv" "$_PROFILES_DEFAULT_PASSWORD" <<'CHROOT_USER'
set -e
NAME="$1"; LOGIN_SHELL="$2"; GROUPS_CSV="$3"; PASSWORD="$4"
if id "$NAME" &>/dev/null; then
  usermod -s "$LOGIN_SHELL" "$NAME"
  if [[ -n "$GROUPS_CSV" ]]; then
    usermod -G "$GROUPS_CSV" "$NAME"
  fi
else
  if [[ -n "$GROUPS_CSV" ]]; then
    useradd -m -s "$LOGIN_SHELL" -G "$GROUPS_CSV" "$NAME"
  else
    useradd -m -s "$LOGIN_SHELL" "$NAME"
  fi
fi
printf '%s:%s\n' "$NAME" "$PASSWORD" | chpasswd
CHROOT_USER
}

_profiles_install_system_program() {
  local prog="$1"
  local rel
  rel="$(_profiles_resolve_program "$prog")"
  info "Installing system program: ${prog}  (.os/programs/${rel})"
  arch-chroot "$MOUNT_ROOT" /usr/bin/env \
    OS_DIR="${_PROFILES_RUNTIME_DIR}" \
    PROGRAMS="${_PROFILES_RUNTIME_DIR}/programs" \
    SHELL_COMMONS="${_PROFILES_RUNTIME_DIR}/lib" \
    /usr/bin/bash "${_PROFILES_RUNTIME_DIR}/programs/${rel}/install.sh"
}

# Temporarily grant NOPASSWD sudo to a user. Required for paru/makepkg to
# install built packages via pacman during the chroot install.
_profiles_grant_temp_sudo() {
  local user="$1"
  printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$user" \
    >"${MOUNT_ROOT}${_PROFILES_SUDO_DROPIN}"
  chmod 440 "${MOUNT_ROOT}${_PROFILES_SUDO_DROPIN}"
}

_profiles_revoke_temp_sudo() {
  rm -f "${MOUNT_ROOT}${_PROFILES_SUDO_DROPIN}"
}

# Bootstrap paru as <user> via AUR + makepkg, inside the chroot.
# Skips if paru is already on PATH for the user.
_profiles_bootstrap_paru() {
  local user="$1"
  info "Bootstrapping paru for user: ${user}"
  arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- "$user" <<'CHROOT_PARU'
set -e
USER_NAME="$1"
if su - "$USER_NAME" -c 'command -v paru >/dev/null 2>&1'; then
  echo "  paru already installed for ${USER_NAME}"
  exit 0
fi
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
BUILD="${HOME_DIR}/.paru-bootstrap"
rm -rf "$BUILD"
su - "$USER_NAME" -c "
  set -e
  git clone --depth 1 https://aur.archlinux.org/paru.git '${BUILD}'
  cd '${BUILD}'
  makepkg -si --noconfirm --skipreview
"
rm -rf "$BUILD"
CHROOT_PARU
}

_profiles_install_user_program() {
  local user="$1" prog="$2"
  local rel
  rel="$(_profiles_resolve_program "$prog")"
  info "Installing user program: ${prog}  (user=${user}, .os/programs/${rel})"
  arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- \
    "$user" \
    "${_PROFILES_RUNTIME_DIR}" \
    "${_PROFILES_RUNTIME_DIR}/programs/${rel}/install.sh" <<'CHROOT_USERPROG'
set -e
USER_NAME="$1"; OS_DIR_IN="$2"; INSTALL_SH="$3"
su - "$USER_NAME" -c "
  export OS_DIR='${OS_DIR_IN}'
  export PROGRAMS='${OS_DIR_IN}/programs'
  export SHELL_COMMONS='${OS_DIR_IN}/lib'
  bash '${INSTALL_SH}'
"
CHROOT_USERPROG
}

# =============================================================================
# PUBLIC ENTRY POINT
# =============================================================================

run_profiles() {
  section "Profiles Runner"

  local hostname="${RESOLVED_HOSTNAME:-}"
  if [[ -z "$hostname" ]]; then
    warn "RESOLVED_HOSTNAME unset — skipping profiles runner."
    return 0
  fi

  # OS_DIR is consumed by configs.sh and exported so program install.sh
  # scripts can locate the staged runtime tree.
  export OS_DIR="${SCRIPT_DIR}"

  if [[ ! -f "${OS_DIR}/hosts/core/config.jsonc" ]]; then
    warn "Hosts core config not found at ${OS_DIR}/hosts/core/config.jsonc — skipping profiles runner."
    return 0
  fi
  if [[ ! -f "${OS_DIR}/users/core/config.jsonc" ]]; then
    warn "Users core config not found at ${OS_DIR}/users/core/config.jsonc — skipping profiles runner."
    return 0
  fi

  local host_json rc=0
  host_json="$(load_host_config "$hostname" 2>/dev/null)" || rc=$?
  case "$rc" in
  0) info "Loaded host config: ${hostname}" ;;
  1)
    warn "No host config at ${OS_DIR}/hosts/${hostname}/ — skipping profiles runner."
    return 0
    ;;
  2)
    warn "Hosts core config could not be loaded — skipping profiles runner."
    return 0
    ;;
  3) error "Reserved hostname 'core' cannot be installed." ;;
  *) error "Unexpected return code ${rc} from load_host_config." ;;
  esac

  local -a users sys_progs
  mapfile -t users < <(printf '%s' "$host_json" | jq -r '.users[]?')
  mapfile -t sys_progs < <(printf '%s' "$host_json" | jq -r '.system_programs[]?')

  # ── Validation ────────────────────────────────────────────────────────────
  # Every user referenced by the host config must have a directory.
  local u
  for u in "${users[@]}"; do
    [[ -d "${OS_DIR}/users/${u}" ]] ||
      error "Host config references user '${u}' but ${OS_DIR}/users/${u}/ does not exist."
  done

  # All host-level programs must exist and be marked system: true.
  if ((${#sys_progs[@]} > 0)); then
    _profiles_validate_programs "true" "${sys_progs[@]}"
  fi

  # Pre-load every user config and validate their program lists.
  declare -A USER_JSONS=()
  for u in "${users[@]}"; do
    local uj urc=0
    uj="$(load_user_config "$u" 2>/dev/null)" || urc=$?
    case "$urc" in
    0 | 1) USER_JSONS["$u"]="$uj" ;;
    2) error "Users core config could not be loaded." ;;
    3) error "User '${u}' is named 'core' (reserved)." ;;
    *) error "Unexpected return code ${urc} from load_user_config for '${u}'." ;;
    esac

    local -a uprogs=()
    mapfile -t uprogs < <(printf '%s' "${USER_JSONS[$u]}" | jq -r '.programs[]?')
    if ((${#uprogs[@]} > 0)); then
      _profiles_validate_programs "false" "${uprogs[@]}"
    fi
  done

  # ── Stage runtime, create users, install programs ────────────────────────
  _profiles_stage_runtime

  for u in "${users[@]}"; do
    _profiles_create_user "$u" "${USER_JSONS[$u]}"
  done

  local prog
  for prog in "${sys_progs[@]}"; do
    _profiles_install_system_program "$prog"
  done

  for u in "${users[@]}"; do
    local -a uprogs=()
    mapfile -t uprogs < <(printf '%s' "${USER_JSONS[$u]}" | jq -r '.programs[]?')
    ((${#uprogs[@]} > 0)) || continue

    _profiles_grant_temp_sudo "$u"
    _profiles_bootstrap_paru "$u"
    for prog in "${uprogs[@]}"; do
      _profiles_install_user_program "$u" "$prog"
    done
    _profiles_revoke_temp_sudo
  done

  _profiles_cleanup
  info "Profiles runner complete."
}
