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
#   - Program not found / system flag mismatch → hard error
#     (validation lives in lib/configs.sh and runs before any side effects).
#   - Staged runtime missing pieces   → hard error (caught by
#     _profiles_validate_staging before any program runs).
#
# Program execution:
#   Every Program Install Script is invoked via lib/run-program.sh, which
#   verifies the chroot-side staging, sources Shell Stdlib once, and sources
#   the install.sh in the same shell. Programs do not need to source stdlib
#   themselves.
#
# Exports inside arch-chroot for each program install.sh:
#   OS_DIR, PROGRAMS, SHELL_COMMONS
# =============================================================================

readonly _PROFILES_DEFAULT_PASSWORD="12345"
readonly _PROFILES_RUNTIME_DIR="/var/tmp/.os-runtime"
readonly _PROFILES_SUDO_DROPIN="/etc/sudoers.d/01-profiles-runner"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Stage program tree + Shell Stdlib + program runner inside the chroot so
# install.sh scripts can run via arch-chroot with stable, predictable paths.
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
  cp "${OS_DIR}/lib/run-program.sh"  "$target/lib/run-program.sh"
  chmod +x "$target/lib/run-program.sh"
  find "$target/programs" -name '*.sh' -exec chmod +x {} \;
}

# Verify the staged tree is complete before invoking any install.sh. Catches
# partial copies / I/O failures early so the first program doesn't fail with
# an opaque "stdlib not found" error mid-execution.
_profiles_validate_staging() {
  local target="${MOUNT_ROOT}${_PROFILES_RUNTIME_DIR}"
  [[ -d "$target/programs" ]] ||
    error "Staging incomplete: ${target}/programs missing."
  [[ -r "$target/lib/shell-stdlib.sh" ]] ||
    error "Staging incomplete: ${target}/lib/shell-stdlib.sh missing or unreadable."
  [[ -r "$target/lib/run-program.sh" ]] ||
    error "Staging incomplete: ${target}/lib/run-program.sh missing or unreadable."
}

# Remove the staged runtime tree and any leftover sudoers drop-ins.
# Idempotent — safe to call from finalize and from error traps.
_profiles_cleanup() {
  rm -rf "${MOUNT_ROOT}${_PROFILES_RUNTIME_DIR}"
  rm -f "${MOUNT_ROOT}${_PROFILES_SUDO_DROPIN}"
}

resolve_user_groups() {
  local json="$1"
  printf '%s' "$json" | jq -r '
    (.groups // []) +
    (if .sudo == true and ((.groups // []) | index("wheel") == null)
      then ["wheel"] else [] end)
    | unique_by(.) | join(",")
  '
}

_profiles_create_user() {
  local name="$1" json="$2"
  local shell sudo_flag groups_csv
  shell="$(printf '%s' "$json" | jq -r '.shell // "/bin/bash"')"
  sudo_flag="$(printf '%s' "$json" | jq -r '.sudo // false')"
  groups_csv="$(resolve_user_groups "$json")"
  info "Creating user: ${name}  (shell=${shell}, sudo=${sudo_flag}, groups=${groups_csv:-<none>})"
  arch-chroot "$MOUNT_ROOT" /usr/bin/bash /root/lib-chroot/create-user.sh \
    "$name" "$shell" "$groups_csv" "$_PROFILES_DEFAULT_PASSWORD"
}

# Re-apply the full group list for a user. Run after all programs are installed
# so package-created groups (docker, libvirt, kvm, …) now exist in the chroot.
_profiles_apply_user_groups() {
  local name="$1" json="$2"
  local groups_csv
  groups_csv="$(resolve_user_groups "$json")"
  [[ -z "$groups_csv" ]] && return 0
  info "Reconciling groups for user: ${name}  (groups=${groups_csv})"
  arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- "$name" "$groups_csv" <<'CHROOT_GROUPS'
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

_profiles_install_system_program() {
  local prog="$1"
  local rel
  rel="$(resolve_program "$prog")"
  info "Installing system program: ${prog}  (.os/programs/${rel})"
  arch-chroot "$MOUNT_ROOT" /usr/bin/env \
    OS_DIR="${_PROFILES_RUNTIME_DIR}" \
    PROGRAMS="${_PROFILES_RUNTIME_DIR}/programs" \
    SHELL_COMMONS="${_PROFILES_RUNTIME_DIR}/lib" \
    /usr/bin/bash "${_PROFILES_RUNTIME_DIR}/lib/run-program.sh" \
    "${_PROFILES_RUNTIME_DIR}/programs/${rel}/install.sh"
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
  makepkg -si --noconfirm
"
rm -rf "$BUILD"
CHROOT_PARU
}

_profiles_install_user_program() {
  local user="$1" prog="$2"
  local rel
  rel="$(resolve_program "$prog")"
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
  bash '${OS_DIR_IN}/lib/run-program.sh' '${INSTALL_SH}'
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
    validate_programs "true" "${sys_progs[@]}" || error "Host config references invalid system programs."
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
      validate_programs "false" "${uprogs[@]}" || error "User '${u}' config references invalid user programs."
    fi
  done

  # ── Stage runtime, validate it, create users, install programs ───────────
  _profiles_stage_runtime
  _profiles_validate_staging

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
    # Install AUR GPU packages (e.g. envycontrol for hybrid setups) via paru
    # for the primary user, before user programs run.
    if [[ "${u}" == "${users[0]}" && "${#GPU_PARU_PACKAGES[@]}" -gt 0 ]]; then
      info "Installing GPU AUR packages for ${u}: ${GPU_PARU_PACKAGES[*]}"
      arch-chroot "$MOUNT_ROOT" su - "$u" -c         "paru -S --noconfirm --needed ${GPU_PARU_PACKAGES[*]}"
    fi
    for prog in "${uprogs[@]}"; do
      _profiles_install_user_program "$u" "$prog"
    done
    _profiles_revoke_temp_sudo
  done

  # Re-apply full group memberships now that package-created groups exist.
  for u in "${users[@]}"; do
    _profiles_apply_user_groups "$u" "${USER_JSONS[$u]}"
  done

  _profiles_cleanup
  info "Profiles runner complete."
}
