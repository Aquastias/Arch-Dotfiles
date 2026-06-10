#!/usr/bin/env bash
# =============================================================================
# lib/profiles/runner.sh — Host/user profile runner
# =============================================================================
# Sourced by 03-install.sh after configure_system().
# Requires: lib/common.sh and lib/config/layers.sh already sourced.
#
# Public API:
#   run_profiles  Entry point. Reads merged host config for $RESOLVED_HOST_PROFILE,
#                 creates users, installs system programs, bootstraps paru per
#                 user, installs user programs, then cleans up the staged tree.
#
# Behaviour for missing pieces:
#   - Hosts/users core config missing → warn and return (graceful).
#   - Specific host config missing    → warn and return (graceful).
#   - User dir referenced but missing → hard error.
#   - Program not found / system flag mismatch → hard error
#     (validation lives in lib/config/layers.sh and runs before any side effects).
#   - Staged runtime missing pieces   → hard error (caught by
#     validate_staging before any program runs).
#
# Program execution:
#   Every Program Install Script is invoked via lib/profiles/program-runner.sh, which
#   sources Shell Stdlib once and sources the install.sh in the same shell.
#   Programs do not need to source stdlib themselves.
#
# Exports inside arch-chroot for each program install.sh:
#   OS_DIR, PROGRAMS, SHELL_COMMONS
# =============================================================================

readonly _PROFILES_DEFAULT_PASSWORD="12345"
readonly _PROFILES_RUNTIME_DIR="/var/tmp/.os-runtime"
readonly _PROFILES_SUDO_DROPIN="/etc/sudoers.d/01-profiles-runner"
# Paths (relative to the runtime root) that constitute a valid staged tree.
# Both _profiles_stage_runtime and validate_staging iterate this array so the
# contract lives in one place.
readonly -a _STAGED_RUNTIME_FILES=(
  "lib/shell-stdlib.sh"
  "lib/shell"
  "lib/profiles/program-runner.sh"
  "lib/grub-common.sh"
)

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
  local f
  for f in "${_STAGED_RUNTIME_FILES[@]}"; do
    mkdir -p "$(dirname "$target/${f}")"
    cp -r "${OS_DIR}/${f}" "$target/${f}"
  done
  chmod +x "$target/lib/profiles/program-runner.sh"
  find "$target/programs" -name '*.sh' -exec chmod +x {} \;
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

# Pure predicate: true (0) iff install-state at <path> records any secret —
# `.secrets.host` set or `.secrets.users` non-empty. False (1) otherwise,
# including a missing file. Reads only; no side effects. Drives implicit
# sops activation in run_profiles (ADR 0025).
_profiles_host_uses_secrets() {
  local state="$1"
  [[ -f "$state" ]] || return 1
  jq -e '(.secrets.host // "") != ""
    or ((.secrets.users // {}) | length > 0)' "$state" >/dev/null 2>&1
}

# Pure list-shaper: echoes the system-program list (one per line) with
# `sops` appended when <active> is "1" and `sops` is not already present.
# Dedupes against declared programs; leaves the list untouched when inactive.
# Args: <active 0|1> [prog...].
_profiles_sops_selection() {
  local active="$1"; shift
  local -a progs=("$@")
  if [[ "$active" == "1" ]]; then
    local p has=0
    for p in "${progs[@]+"${progs[@]}"}"; do
      [[ "$p" == "sops" ]] && has=1
    done
    ((has)) || progs+=("sops")
  fi
  ((${#progs[@]})) && printf '%s\n' "${progs[@]}"
}

# Pure resolver for the Runner AUR pass. Unions host packages.aur (categorized
# string mode) with each desktop adapter's `aur` field (categorized bool mode),
# read from ${OS_DIR}/extras/desktop/<de>/install-<de>.jsonc. Prints the
# sorted-unique union, one per line. A missing host field, adapter file, or
# adapter `aur` field contributes nothing. Parses are captured by command
# substitution (not process substitution) so a parser error() abort propagates
# here rather than being swallowed. Args: <host_json> [desktop...].
_profiles_resolve_aur() {
  local host_json="$1"; shift
  local -a out=()
  local parsed

  local host_aur_json
  host_aur_json="$(printf '%s' "$host_json" | jq -c '.packages.aur // empty')"
  if [[ -n "$host_aur_json" ]]; then
    parsed="$(categorized_list_parse "$host_aur_json" string packages.aur)" \
      || return 1
    [[ -n "$parsed" ]] && mapfile -t -O "${#out[@]}" out <<< "$parsed"
  fi

  local de adapter aur_json
  for de in "$@"; do
    adapter="${OS_DIR}/extras/desktop/${de}/install-${de}.jsonc"
    [[ -f "$adapter" ]] || continue
    aur_json="$(jsonc_strip "$adapter" | jq -c '.aur // empty')"
    [[ -n "$aur_json" ]] || continue
    parsed="$(categorized_list_parse "$aur_json" bool aur)" || return 1
    [[ -n "$parsed" ]] && mapfile -t -O "${#out[@]}" out <<< "$parsed"
  done

  ((${#out[@]})) || return 0
  printf '%s\n' "${out[@]}" | sort -u
}

_profiles_resolve_user_secrets() {
  local name="$1"
  local host_state="${MOUNT_ROOT}/install-state.json"
  [[ -f "$host_state" ]] || return 0
  local raw_path
  raw_path="$(jq -r --arg n "$name" \
    '.secrets.users[$n] // empty' "$host_state")"
  [[ -n "$raw_path" && -f "$raw_path" ]] || return 0
  local chroot_dir="${MOUNT_ROOT}${_PROFILES_RUNTIME_DIR}/secrets"
  mkdir -p "$chroot_dir"
  cp "$raw_path" "${chroot_dir}/${name}-secrets.json"
  printf '%s' "${_PROFILES_RUNTIME_DIR}/secrets/${name}-secrets.json"
}

_profiles_create_user() {
  local name="$1" json="$2"
  local shell sudo_flag groups_csv
  shell="$(printf '%s' "$json" | jq -r '.shell // "/bin/bash"')"
  sudo_flag="$(printf '%s' "$json" | jq -r '.sudo // false')"
  groups_csv="$(resolve_user_groups "$json")"
  info "Creating user: ${name}" \
       "(shell=${shell}, sudo=${sudo_flag}, groups=${groups_csv:-<none>})"
  local sec_path
  sec_path="$(_profiles_resolve_user_secrets "$name")"
  arch-chroot "$MOUNT_ROOT" /usr/bin/bash /root/lib-chroot/create-user.sh \
    "$name" "$shell" "$groups_csv" "$_PROFILES_DEFAULT_PASSWORD" \
    ${sec_path:+"$sec_path"}
}

# Re-apply the full group list for a user. Run after all programs are installed
# so package-created groups (docker, libvirt, kvm, …) now exist in the chroot.
_profiles_apply_user_groups() {
  local name="$1" json="$2"
  local groups_csv
  groups_csv="$(resolve_user_groups "$json")"
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

_profiles_install_system_program() {
  local prog="$1"
  local rel
  rel="$(resolve_program "$prog")"
  info "Installing system program: ${prog}  (.os/programs/${rel})"
  arch-chroot "$MOUNT_ROOT" /usr/bin/env \
    OS_DIR="${_PROFILES_RUNTIME_DIR}" \
    PROGRAMS="${_PROFILES_RUNTIME_DIR}/programs" \
    SHELL_COMMONS="${_PROFILES_RUNTIME_DIR}/lib" \
    /usr/bin/bash "${_PROFILES_RUNTIME_DIR}/lib/profiles/program-runner.sh" \
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

# Resolve + install an AUR set for a user. A print-only pre-flight pass runs
# first in the real installed environment, so a provider/conflict failure — a
# virtual dep (e.g. libjpeg6) whose default provider conflicts with an already
# installed package — aborts *before* any download, with an actionable hint,
# instead of the bare ERR-trap line number. The real install then streams live.
_profiles_aur_install() {
  local user="$1"; shift
  local -a pkgs=("$@")
  ((${#pkgs[@]} > 0)) || return 0

  info "Pre-flight resolving AUR set for ${user}..."
  local out rc=0
  out="$(arch-chroot "$MOUNT_ROOT" su - "$user" -c \
    "paru -Sp --noconfirm --needed ${pkgs[*]}" 2>&1)" || rc=$?
  if ((rc != 0)); then
    if grep -qE "conflicting packages|Conflicts found" <<< "$out"; then
      _profiles_aur_conflict_report "$out"
      error "AUR pre-flight found an unresolvable conflict for ${user}." \
            "Pin a non-conflicting provider, then re-run."
    fi
    # Non-conflict failure (e.g. transient resolver hiccup): warn, let the real
    # pass surface it through the normal ERR trap.
    warn "AUR pre-flight returned non-zero with no conflict signature;" \
         "proceeding to install."
    printf '%s\n' "$out" >&2
  fi

  arch-chroot "$MOUNT_ROOT" su - "$user" -c \
    "paru -S --noconfirm --needed ${pkgs[*]}"
}

# Surface a provider conflict from captured paru resolution output. The output
# already holds the provider menus, the 'Conflicts found:' block, and the
# 'can not install conflicting packages' error — print it, framed by guidance.
_profiles_aur_conflict_report() {
  local out="$1"
  warn "AUR provider conflict: a package's default provider conflicts with" \
       "an already-installed package, and paru can not confirm conflicts" \
       "under --noconfirm. Resolver output follows:"
  printf '%s\n' "$out" >&2
  warn "Fix: pin a non-conflicting provider in the host's packages.aur" \
       "(e.g. 'libjpeg6-turbo' to satisfy a 'libjpeg6' dependency)."
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
  bash '${OS_DIR_IN}/lib/profiles/program-runner.sh' '${INSTALL_SH}'
"
CHROOT_USERPROG
}


_profiles_write_authorized_keys() {
  local user="$1" json="$2"
  local -a keys=()
  mapfile -t keys < <(printf '%s' "$json" \
    | jq -r '.ssh_authorized_keys[]?' 2>/dev/null)
  ((${#keys[@]} > 0)) || return 0
  info "Writing authorized_keys for user: ${user}  (${#keys[@]} key(s))"
  local tmp="${MOUNT_ROOT}/tmp/.authorized_keys_${user}"
  printf '%s\n' "${keys[@]}" > "$tmp"
  arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- \
    "$user" "/tmp/.authorized_keys_${user}" <<'CHROOT_AUTHKEYS'
set -e
USER_NAME="$1"; KEYS_TMP="$2"
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
mkdir -p "${HOME_DIR}/.ssh"
chmod 700 "${HOME_DIR}/.ssh"
cp "$KEYS_TMP" "${HOME_DIR}/.ssh/authorized_keys"
rm -f "$KEYS_TMP"
chmod 600 "${HOME_DIR}/.ssh/authorized_keys"
chown -R "${USER_NAME}:${USER_NAME}" "${HOME_DIR}/.ssh"
CHROOT_AUTHKEYS
}

_profiles_enable_system_services() {
  local prog="$1"
  local rel config_file
  rel="$(resolve_program "$prog")"
  config_file="${OS_DIR}/programs/${rel}/config.jsonc"
  local -a svcs=()
  mapfile -t svcs < <(jsonc_strip "$config_file" \
    | jq -r '.system_services[]?' 2>/dev/null)
  ((${#svcs[@]} > 0)) || return 0
  local svc
  for svc in "${svcs[@]}"; do
    info "Enabling system service: ${svc}"
    arch-chroot "$MOUNT_ROOT" systemctl enable "$svc"
  done
}

_profiles_enable_user_services() {
  local user="$1" prog="$2"
  local rel config_file
  rel="$(resolve_program "$prog")"
  config_file="${OS_DIR}/programs/${rel}/config.jsonc"
  local -a svcs=()
  mapfile -t svcs < <(jsonc_strip "$config_file" \
    | jq -r '.user_services[]?' 2>/dev/null)
  ((${#svcs[@]} > 0)) || return 0
  local svc
  for svc in "${svcs[@]}"; do
    info "Enabling user service: ${svc}  (user=${user})"
    arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- \
      "$user" "$svc" <<'CHROOT_USERSVC'
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

# _profiles_resolve_user_unit <svc> <search_dir...>
# Echo the path to <svc>.service found in the given roots, or return 1 (no
# output) when absent. Pure: searches the given dirs only.
_profiles_resolve_user_unit() {
  local svc="$1"; shift
  local f
  f="$(find "$@" -name "${svc}.service" 2>/dev/null | head -1)"
  [[ -n "$f" ]] || return 1
  printf '%s\n' "$f"
}

# _profiles_enable_profile_user_services <user> <user_json>
# Enable a user profile's user_services[] — the offline equivalent of
# `systemctl --user enable`: a symlink into the user's
# default.target.wants. Runs after the user's programs + dotfiles are placed.
# A listed unit that isn't installed aborts with an actionable message (the
# per-program list, by contrast, skips a missing unit).
_profiles_enable_profile_user_services() {
  local user="$1" json="$2"
  local -a svcs=()
  mapfile -t svcs < <(printf '%s' "$json" | jq -r '.user_services[]?')
  ((${#svcs[@]} > 0)) || return 0
  local svc
  for svc in "${svcs[@]}"; do
    if ! _profiles_resolve_user_unit "$svc" \
         "${MOUNT_ROOT}/usr/lib/systemd/user" \
         "${MOUNT_ROOT}/usr/local/lib/systemd/user" \
         "${MOUNT_ROOT}/etc/systemd/user" >/dev/null; then
      error "User '${user}' lists user_service '${svc}', but no" \
            "${svc}.service unit is installed. Declare the program that" \
            "provides it before this entry, or fix the name."
      return 1
    fi
    info "Enabling user service: ${svc}  (user=${user})"
    arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- \
      "$user" "$svc" <<'CHROOT_PROFILE_USERSVC'
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

_profiles_clone_dotfiles() {
  local user="$1" repo="$2"
  [[ -n "$repo" ]] || return 0
  info "Cloning dotfiles for user: ${user}  (${repo})"
  arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- \
    "$user" "$repo" <<'CHROOT_DOTFILES'
set -e
USER_NAME="$1"; REPO="$2"
CLONE_SCRIPT="$(mktemp)"
cat > "$CLONE_SCRIPT" <<CLONE_INNER
set -e
DOTFILES="\${HOME}/.dotfiles"
if [[ -d "\$DOTFILES" ]]; then
  echo "  dotfiles dir exists — skipping" >&2
  exit 0
fi
git clone "${REPO}" "\$DOTFILES"
cd "\$DOTFILES"
"\$DOTFILES/.os/tools/generate-configs.sh" --user "${USER_NAME}"
source "\$DOTFILES/.os/lib/config/generator.sh"
mapfile -t _pkgs < <(cg_legacy_packages ".")
stow --no-folding "\${_pkgs[@]}"
stow -d "\$DOTFILES/.stow/${USER_NAME}" --no-folding .
CLONE_INNER
su - "$USER_NAME" -c "bash '$CLONE_SCRIPT'"
rm -f "$CLONE_SCRIPT"
CHROOT_DOTFILES
}


_profiles_apply_sysctl() {
  local host_json="$1"
  local sysctl_json
  sysctl_json="$(printf '%s' "$host_json" \
    | jq -c '.sysctl // empty' 2>/dev/null)"
  [[ -n "$sysctl_json" ]] || return 0
  info "Writing sysctl defaults to /etc/sysctl.d/99-os.conf"
  mkdir -p "${MOUNT_ROOT}/etc/sysctl.d"
  printf '%s' "$sysctl_json" \
    | jq -r 'to_entries[] | "\(.key) = \(.value)"' \
    > "${MOUNT_ROOT}/etc/sysctl.d/99-os.conf"
}

# =============================================================================
# PUBLIC ENTRY POINT
# =============================================================================

run_profiles() {
  section "Profiles Runner"

  local profile="${RESOLVED_HOST_PROFILE:-}"
  if [[ -z "$profile" ]]; then
    warn "RESOLVED_HOST_PROFILE unset — skipping profiles runner."
    return 0
  fi

  # OS_DIR is consumed by configs.sh and exported so program install.sh
  # scripts can locate the staged runtime tree.
  export OS_DIR="${SCRIPT_DIR}"

  if [[ ! -f "${OS_DIR}/hosts/core/config.jsonc" ]]; then
    warn "Hosts core config not found at" \
         "${OS_DIR}/hosts/core/config.jsonc — skipping profiles runner."
    return 0
  fi
  if [[ ! -f "${OS_DIR}/users/core/config.jsonc" ]]; then
    warn "Users core config not found at" \
         "${OS_DIR}/users/core/config.jsonc — skipping profiles runner."
    return 0
  fi

  # ADR 0036: read the host's software (users / system_programs / sysctl /
  # packages) from the assembled effective config — the single source of truth
  # the front-end produced (install.sh --profile or the VM seed) — not the
  # legacy per-host config.jsonc, which migrated hosts (profile.jsonc) no longer
  # ship. CONFIG_FILE is set by 03-install.sh.
  local host_json
  if ! host_json="$(jsonc_read "$CONFIG_FILE" '.' 2>/dev/null)" \
     || [[ -z "$host_json" || "$host_json" == "null" ]]; then
    warn "Runner: cannot read effective config at ${CONFIG_FILE}" \
         "— skipping profiles runner."
    return 0
  fi
  info "Loaded effective config for: ${profile}"

  _profiles_apply_sysctl "$host_json"

  local -a users sys_progs
  mapfile -t users < <(printf '%s' "$host_json" | jq -r '.users[]?')
  mapfile -t sys_progs < <(printf '%s' "$host_json" \
    | jq -r '.system_programs[]?')

  # Implicit sops activation (ADR 0025): sops is not declared in any host
  # config; the Runner selects it through the normal system-program path
  # only when install-state records secrets, deduped against declarations.
  local _sec_active=0
  if _profiles_host_uses_secrets "${MOUNT_ROOT}/install-state.json"; then
    _sec_active=1
  fi
  mapfile -t sys_progs < <(_profiles_sops_selection "$_sec_active" \
    "${sys_progs[@]+"${sys_progs[@]}"}")

  # Pre-load user configs for install execution.
  # Program contract validation was done by validate_install_context.
  declare -A USER_JSONS=()
  local u
  for u in "${users[@]}"; do
    local uj urc=0
    uj="$(load_user_config "$u" 2>/dev/null)" || urc=$?
    case "$urc" in
    0 | 1) USER_JSONS["$u"]="$uj" ;;
    2) error "Users core config could not be loaded." ;;
    3) error "User '${u}' is named 'core' (reserved)." ;;
    *) error "Unexpected return code ${urc} from" \
             "load_user_config for '${u}'." ;;
    esac
  done

  local dotfiles_repo
  dotfiles_repo="$(install_config_dotfiles_repo)"

  # ── Stage runtime, validate it, create users, install programs ───────────
  _profiles_stage_runtime
  validate_staging "${MOUNT_ROOT}${_PROFILES_RUNTIME_DIR}"

  for u in "${users[@]}"; do
    _profiles_create_user "$u" "${USER_JSONS[$u]}"
    _profiles_write_authorized_keys "$u" "${USER_JSONS[$u]}"
  done

  local prog
  for prog in "${sys_progs[@]}"; do
    _profiles_install_system_program "$prog"
    _profiles_enable_system_services "$prog"
  done

  # Resolve the AUR set: host packages.aur ∪ each desktop adapter's `aur`
  # list, deduped into a single paru pass (pkg-categorization slice 06).
  # Aborts here on a malformed list (resolver propagates the parser error).
  local -a host_aur=()
  local _aur_out
  _aur_out="$(_profiles_resolve_aur "$host_json" \
    "${ENVIRONMENT_DESKTOP[@]+"${ENVIRONMENT_DESKTOP[@]}"}")"
  [[ -n "$_aur_out" ]] && mapfile -t host_aur <<< "$_aur_out"

  for u in "${users[@]}"; do
    local -a uprogs=()
    mapfile -t uprogs < <(printf '%s' "${USER_JSONS[$u]}" \
      | jq -r '.programs[]?')

    # Bootstrap paru for this user if they have programs, or if they are the
    # primary user and there are host/GPU AUR packages to install.
    local needs_paru=0
    ((${#uprogs[@]} > 0)) && needs_paru=1
    [[ "${u}" == "${users[0]}" ]] \
      && ((${#host_aur[@]} + ${#GPU_PARU_PACKAGES[@]} > 0)) \
      && needs_paru=1
    ((needs_paru)) || continue

    _profiles_grant_temp_sudo "$u"
    _profiles_bootstrap_paru "$u"
    # Install host AUR packages and GPU AUR packages for the primary user.
    if [[ "${u}" == "${users[0]}" ]]; then
      local -a primary_aur=(
        "${host_aur[@]+"${host_aur[@]}"}"
        "${GPU_PARU_PACKAGES[@]+"${GPU_PARU_PACKAGES[@]}"}"
      )
      if ((${#primary_aur[@]} > 0)); then
        info "Installing AUR packages for ${u}: ${#primary_aur[@]} packages"
        _profiles_aur_install "$u" "${primary_aur[@]}"
      fi
    fi
    for prog in "${uprogs[@]}"; do
      # Reconcile the reference (ADR 0036): a system:false program installs
      # at user level; a system program the host already installs is a no-op;
      # a system program no host installs aborts (reconcile prints why).
      local _action
      _action="$(reconcile_user_program "$prog" \
        "${sys_progs[@]+"${sys_progs[@]}"}")" \
        || error "User '${u}': cannot reconcile program '${prog}'."
      case "$_action" in
      user)
        _profiles_install_user_program "$u" "$prog"
        _profiles_enable_user_services "$u" "$prog"
        ;;
      noop)
        info "User '${u}': '${prog}' already installed by the host" \
             "— skipping user-level install."
        ;;
      esac
    done
    _profiles_revoke_temp_sudo
  done

  # Re-apply full group memberships now that package-created groups exist.
  # Then clone dotfiles and stow for each user.
  for u in "${users[@]}"; do
    _profiles_apply_user_groups "$u" "${USER_JSONS[$u]}"
    _profiles_clone_dotfiles "$u" "$dotfiles_repo"
    # user_services run last — after the user's programs + dotfiles placed
    # the providing units, so a missing unit is a real error.
    _profiles_enable_profile_user_services "$u" "${USER_JSONS[$u]}"
  done

  _profiles_cleanup
  info "Profiles runner complete."
}
