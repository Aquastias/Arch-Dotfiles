#!/usr/bin/env bash
# =============================================================================
# lib/profiles/runner.sh — Host/user profile runner
# =============================================================================
# Sourced by 03-install.sh after chroot_configure_system().
# Requires: lib/common.sh and lib/config/program-registry.sh already sourced.
#
# Public API:
#   runner_run_profiles  Entry point. Reads merged host config for $RESOLVED_HOST_PROFILE,
#                 creates users, installs Host Programs, bootstraps paru per
#                 user, installs user programs, then cleans up the staged tree.
#
# Behaviour for missing pieces:
#   - Hosts/users core config missing → warn and return (graceful).
#   - Specific host config missing    → warn and return (graceful).
#   - User dir referenced but missing → hard error.
#   - Program not found / system flag mismatch → hard error
#     (validation lives in lib/config/program-registry.sh and runs before any
#     side effects).
#   - Staged runtime missing pieces   → hard error (caught by
#     validation_check_staging before any program runs).
#
# Program execution:
#   Every Program Install Script is invoked via lib/profiles/program-runner.sh, which
#   sources Shell Stdlib once and sources the install.sh in the same shell.
#   Programs do not need to source stdlib themselves.
#
# Exports inside arch-chroot for each program install.sh:
#   INSTALLER_DIR, PROGRAMS, SHELL_COMMONS
#   AUR_HELPER (user-program path only) — the resolved AUR Helper (ADR 0052),
#     paru or yay, for scripts that install via `${AUR_HELPER} -S`.
# =============================================================================

# shellcheck source=../config/post-install.sh
declare -F post_install_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/post-install.sh"

# Install State owns the credential-key resolution + SOPS gate; source it if a
# standalone unit test pulled runner.sh in without the installer's load order.
# shellcheck source=../install-state.sh
declare -F install_state_credential_path >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../install-state.sh"

# AUR Helper resolution rule (aur_helper_detect), shared with
# tools/install-pkglist.sh so it has a single definition (ADR 0052).
# shellcheck source=../aur-helper.sh
declare -F aur_helper_detect >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../aur-helper.sh"
# shellcheck source=../config/fonts.sh
declare -F fonts_aur_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/fonts.sh"
# Config Apply Planner (ADR 0134): decides which selected programs' home/ config
# to copy for a user, honoring config_exclude. Decoupled from package install.
# shellcheck source=../config/config-apply.sh
declare -F config_apply_plan >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/config-apply.sh"

# The Runner's users, program installs, AUR side, unit enabling, and
# per-user config.
# shellcheck source=./runner-users.sh
source "${BASH_SOURCE[0]%/*}/runner-users.sh"
# shellcheck source=./runner-programs.sh
source "${BASH_SOURCE[0]%/*}/runner-programs.sh"
# shellcheck source=./runner-aur.sh
source "${BASH_SOURCE[0]%/*}/runner-aur.sh"
# shellcheck source=./runner-services.sh
source "${BASH_SOURCE[0]%/*}/runner-services.sh"
# shellcheck source=./runner-user-config.sh
source "${BASH_SOURCE[0]%/*}/runner-user-config.sh"

readonly _RUNNER_DEFAULT_PASSWORD="12345"
readonly _RUNNER_RUNTIME_DIR="/var/tmp/.installer-runtime"
readonly _RUNNER_SUDO_DROPIN="/etc/sudoers.d/01-profiles-runner"
# AUR Vetting (ADR 0143). The rungs and paru's PreBuildCommand call the
# vetter by absolute path, so nothing earlier on a user's PATH stands in.
: "${_RUNNER_AUR_VET_BIN:=/usr/local/bin/aur-vet}"
readonly -a _AUR_VET_SHARE_FILES=(
  scan.awk rules.tsv indicators.tsv campaigns.tsv sources.tsv
)
# Paths (relative to the runtime root) that constitute a valid staged tree. Both
# runner_stage_runtime and validation_check_staging iterate this array so the
# contract lives in one place.
readonly -a _STAGED_RUNTIME_FILES=(
  "lib/shell-stdlib.sh"
  "lib/shell"
  "lib/profiles/program-runner.sh"
)

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# _retry (generic retry-with-backoff) lives in lib/common.sh.

# Stage program tree + Shell Stdlib + program runner inside the chroot so
# install.sh scripts can run via arch-chroot with stable, predictable paths.
runner_stage_runtime() {
  local target="${MOUNT_ROOT}${_RUNNER_RUNTIME_DIR}"
  rm -rf "$target"
  mkdir -p "$target/lib"
  if [[ -d "${INSTALLER_DIR}/programs" ]]; then
    cp -r "${INSTALLER_DIR}/programs" "$target/programs"
  else
    mkdir -p "$target/programs"
  fi
  local file
  for file in "${_STAGED_RUNTIME_FILES[@]}"; do
    mkdir -p "$(parent_directory "$target/${file}")"
    cp -r "${INSTALLER_DIR}/${file}" "$target/${file}"
  done
  chmod +x "$target/lib/profiles/program-runner.sh"
  find "$target/programs" -name '*.sh' -exec chmod +x {} \;
}



# Remove the staged runtime tree and any leftover sudoers drop-ins.
# Idempotent — safe to call from finalize and from error traps.
_runner_cleanup() {
  rm -rf "${MOUNT_ROOT}${_RUNNER_RUNTIME_DIR}"
  rm -f "${MOUNT_ROOT}${_RUNNER_SUDO_DROPIN}"
}

runner_resolve_user_groups() {
  local json="$1"
  printf '%s' "$json" | jq -r '
    (.groups // []) +
    (if .sudo == true and ((.groups // []) | index("wheel") == null)
      then ["wheel"] else [] end)
    | unique_by(.) | join(",")
  '
}

# True (0) iff install-state at <path> records a SOPS secret. Thin delegator
# to the Install State gate (the .secrets-only rule + ADR 0025 invariant live
# there, beside the keys they read). Drives implicit sops activation below.
_runner_host_uses_secrets() {
  install_state_activates_sops "$1"
}

# Pure list-shaper: echoes the system-program list (one per line) with
# `sops` appended when <active> is "1" and `sops` is not already present.
# Dedupes against declared programs; leaves the list untouched when inactive.
# Args: <active 0|1> [prog...].
_runner_sops_selection() {
  local active="$1"; shift
  local -a programs=("$@")
  if [[ "$active" == "1" ]]; then
    local program has=0
    for program in "${programs[@]+"${programs[@]}"}"; do
      [[ "$program" == "sops" ]] && has=1
    done
    ((has)) || programs+=("sops")
  fi
  # `|| return 0`, not `&& printf`: with no programs the arithmetic is false
  # (exit 1), which would trip the install's ERR trap when this feeds a
  # `mapfile < <(...)` — a host with zero host_programs is valid (empty list).
  ((${#programs[@]})) || return 0
  printf '%s\n' "${programs[@]}"
}

# Pure list-shaper for the Security & Backup Extras (M4, ADR 0041). Resolves the
# host post_install.{security,backup} object to its Program names and unions
# them into the Primary User's install list: the user's own programs first (in
# declared order), then the resolved extras not already present (resolver
# canonical order), so a tool declared in both installs once. One per line; the
# whole list empty (no output) is valid. <any_zfs> is required (no silent
# default: a guessed `true` routed zfs-auto-snapshot onto non-ZFS installs).
# Args: <post_install_json> <any_zfs true|false> [uprog...].
runner_resolve_post_install() {
  local pi_json="$1" any_zfs="${2:-}"
  [[ "$any_zfs" == true || "$any_zfs" == false ]] \
    || { error "runner_resolve_post_install: any_zfs must be true|false"; \
         return 1; }
  shift 2
  local -a out=("$@")
  local -a extras=()
  local _extras_text
  _extras_text="$(post_install_programs "$pi_json" "$any_zfs")" || return 1
  [[ -n "$_extras_text" ]] && mapfile -t extras <<< "$_extras_text"

  local extra program has
  for extra in "${extras[@]+"${extras[@]}"}"; do
    has=0
    for program in "${out[@]+"${out[@]}"}"; do
      [[ "$program" == "$extra" ]] && { has=1; break; }
    done
    ((has)) || out+=("$extra")
  done
  ((${#out[@]})) || return 0
  printf '%s\n' "${out[@]}"
}

# Pure resolver for the Runner AUR pass. Unions host packages.aur (categorized
# string mode) with each desktop adapter's `aur` field (categorized bool mode),
# read from ${INSTALLER_DIR}/extras/desktop/<de>/install-<de>.jsonc. Prints the
# sorted-unique union, one per line. A missing host field, adapter file, or
# adapter `aur` field contributes nothing. Parses are captured by command
# substitution (not process substitution) so a parser error() abort propagates
# here rather than being swallowed. Args: <host_json> [desktop...].
_runner_resolve_aur() {
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

  local desktop adapter aur_json
  for desktop in "$@"; do
    adapter="${INSTALLER_DIR}/extras/desktop/${desktop}/install-${desktop}.jsonc"
    [[ -f "$adapter" ]] || continue
    aur_json="$(jsonc_strip "$adapter" | jq -c '.aur // empty')"
    [[ -n "$aur_json" ]] || continue
    parsed="$(categorized_list_parse "$aur_json" bool aur)" || return 1
    [[ -n "$parsed" ]] && mapfile -t -O "${#out[@]}" out <<< "$parsed"
  done

  ((${#out[@]})) || return 0
  printf '%s\n' "${out[@]}" | sort -u
}

# Source-fetch failures that mean "upstream down", not "package broken".
_RUNNER_AUR_UNREACHABLE='failed to download sources'
_RUNNER_AUR_UNREACHABLE+='|RPC failed; HTTP 5[0-9]{2}'
_RUNNER_AUR_UNREACHABLE+='|Could not resolve host|Failed to connect to'



# =============================================================================
# CONFIG APPLY PASS (ADR 0134)
# =============================================================================
# Config is decoupled from package install: install.sh installs the package,
# this pass copies each selected program's home/ tree into the user's $HOME
# (honoring config_exclude) and seeds the machine default into /etc/skel +
# /root. It is a COPY, not a stow — the staged programs tree is ephemeral
# (cleaned up post-install), so symlinks would dangle. `./stow-configs.sh` is the
# operator's day-2 symlink from the persistent clone; both read the one source.

# =============================================================================
# PUBLIC ENTRY POINT
# =============================================================================

# The run state below (host_json, users, system_programs, USER_JSONS,
# host_aur, dotfiles_repo) is declared here and read/filled by the step
# functions that follow, through bash's dynamic scope.
runner_run_profiles() {
  section "Profiles Runner"
  if [[ -z "${RESOLVED_HOST_PROFILE:-}" ]]; then
    warn "RESOLVED_HOST_PROFILE unset — skipping profiles runner."
    return 0
  fi
  # INSTALLER_DIR is consumed by configs.sh and exported so program install.sh
  # scripts can locate the staged runtime tree.
  export INSTALLER_DIR="${SCRIPT_DIR}"

  local host_json
  _runner_effective_config host_json || return 0
  info "Loaded effective config for: ${RESOLVED_HOST_PROFILE}"

  runner_apply_sysctl "$host_json"

  local -a users system_programs host_aur=()
  declare -A USER_JSONS=()
  _runner_load_users_and_programs

  local dotfiles_repo
  dotfiles_repo="$(install_config_dotfiles_repo)"

  # ── Stage runtime, validate it, create users, install programs ───────────
  runner_stage_runtime
  validation_check_staging "${MOUNT_ROOT}${_RUNNER_RUNTIME_DIR}"
  runner_install_aur_vet
  runner_create_users
  runner_install_host_programs
  _runner_resolve_host_aur || return 1

  local user
  for user in "${users[@]}"; do
    _runner_install_user_software "$user"
  done

  _runner_config_apply_pass
  _runner_cleanup
  info "Profiles runner complete."
}

# _runner_effective_config <out-var> — the assembled effective config as
# JSON into <out-var>, or a warning and status 1 when the run must be
# skipped (no core profiles, unreadable config).
_runner_effective_config() {
  local __config_variable="$1" __host_json
  if [[ ! -f "${INSTALLER_DIR}/hosts/core/profile.jsonc" ]]; then
    warn "Hosts core profile not found at" \
         "${INSTALLER_DIR}/hosts/core/profile.jsonc — skipping profiles runner."
    return 1
  fi
  if [[ ! -f "${INSTALLER_DIR}/users/core/profile.jsonc" ]]; then
    warn "Users core profile not found at" \
         "${INSTALLER_DIR}/users/core/profile.jsonc — skipping profiles runner."
    return 1
  fi

  # ADR 0036: read the host's software (users / host_programs / sysctl /
  # packages) from the assembled effective config — the single source of truth
  # the front-end produced (install.sh --profile or the VM seed). CONFIG_FILE
  # is set by 03-install.sh.
  # shellcheck disable=SC2153  # CONFIG_FILE global, set by 03-install.sh
  if ! __host_json="$(jsonc_read "$CONFIG_FILE" '.' 2>/dev/null)" \
     || [[ -z "$__host_json" || "$__host_json" == "null" ]]; then
    warn "Runner: cannot read effective config at ${CONFIG_FILE}" \
         "— skipping profiles runner."
    return 1
  fi
  printf -v "$__config_variable" '%s' "$__host_json"
}

# Fills users, system_programs and USER_JSONS from host_json.
_runner_load_users_and_programs() {
  mapfile -t users < <(printf '%s' "$host_json" | jq -r '.users[]?')
  mapfile -t system_programs < <(printf '%s' "$host_json" \
    | jq -r '.host_programs[]?')

  # Implicit sops activation (ADR 0025): sops is not declared in any host
  # config; the Runner selects it through the normal system-program path
  # only when install-state records secrets, deduped against declarations.
  local secrets_active=0
  if _runner_host_uses_secrets "${MOUNT_ROOT}/install-state.json"; then
    secrets_active=1
  fi
  mapfile -t system_programs < <(_runner_sops_selection "$secrets_active" \
    "${system_programs[@]+"${system_programs[@]}"}")

  # Pre-load user profiles for install execution.
  # Program contract validation was done by validation_check_install_context.
  local user user_json load_status
  for user in "${users[@]}"; do
    load_status=0
    user_json="$(profile_loader_load_user "$user" 2>/dev/null)" \
      || load_status=$?
    case "$load_status" in
    0 | 1) USER_JSONS["$user"]="$user_json" ;;
    2) error "Users core profile could not be loaded." ;;
    3) error "User '${user}' is named 'core' (reserved)." ;;
    *) error "Unexpected return code ${load_status} from" \
             "profile_loader_load_user for '${user}'." ;;
    esac
  done
}

# Fills host_aur: host packages.aur ∪ each desktop adapter's `aur` list,
# deduped into a single paru pass (pkg-categorization slice 06), plus the Font
# Catalog's AUR members. Aborts on a malformed list (the resolver propagates
# the parser error).
_runner_resolve_host_aur() {
  local resolved fonts_aur
  resolved="$(_runner_resolve_aur "$host_json" \
    "${ENVIRONMENT_DESKTOP[@]+"${ENVIRONMENT_DESKTOP[@]}"}")"
  [[ -n "$resolved" ]] && mapfile -t host_aur <<< "$resolved"

  # Font Catalog (ADR 0080): AUR fonts (today ttf-ms-fonts) ride the paru pass
  # too — options.fonts is the single font home, so its AUR members union in
  # here rather than living in packages.aur. Kept out of _runner_resolve_aur
  # (whose contract is host ∪ adapters) so that resolver stays font-agnostic.
  # Absent options.fonts ⇒ the catalog defaults.
  fonts_aur="$(fonts_aur_packages "$host_json")" || return 1
  [[ -n "$fonts_aur" ]] && mapfile -t -O "${#host_aur[@]}" host_aur \
    <<< "$fonts_aur"
  return 0
}

# _runner_install_user_software <user> — the user's programs (and, for the
# Primary User, the host AUR set + Security & Backup Extras) through their
# AUR Helper, under a temporary sudo grant.
_runner_install_user_software() {
  local user="$1" primary=false
  [[ "$user" == "${users[0]}" ]] && primary=true
  local -a user_programs=()
  mapfile -t user_programs < <(printf '%s' "${USER_JSONS[$user]}" \
    | jq -r '.programs[]?')

  # Security & Backup Extras (M4, ADR 0041): the host's structured
  # post_install.{security,backup} selection installs via the Primary User's
  # paru pass, deduped against that user's own programs — a tool declared in
  # both installs once.
  if $primary; then
    local post_install_json
    post_install_json="$(printf '%s' "$host_json" | jq -c '.post_install // {}')"
    mapfile -t user_programs < <(runner_resolve_post_install \
      "$post_install_json" "$(install_config_any_zfs)" \
      "${user_programs[@]+"${user_programs[@]}"}")
  fi

  # Bootstrap paru for this user if they have programs, or if they are the
  # primary user and there are host/GPU AUR packages to install.
  local needs_paru=0
  ((${#user_programs[@]} > 0)) && needs_paru=1
  $primary && ((${#host_aur[@]} + ${#GPU_PARU_PACKAGES[@]} > 0)) \
    && needs_paru=1
  ((needs_paru)) || return 0

  runner_grant_temporary_sudo "$user"
  local helper
  helper="$(runner_bootstrap_helper "$user")"
  [[ "$helper" == paru ]] \
    && runner_wire_paru_hook "${MOUNT_ROOT}/etc/paru.conf" create
  $primary && _runner_install_primary_aur "$user" "$helper"
  local program
  for program in "${user_programs[@]}"; do
    runner_install_user_program "$user" "$program" "$helper"
  done
  runner_quiesce_gpg "$user"
  runner_revoke_temporary_sudo
}

# Install host AUR packages and GPU AUR packages for the primary user.
_runner_install_primary_aur() {
  local user="$1" helper="$2"
  local -a primary_aur=(
    "${host_aur[@]+"${host_aur[@]}"}"
    "${GPU_PARU_PACKAGES[@]+"${GPU_PARU_PACKAGES[@]}"}"
  )
  ((${#primary_aur[@]} > 0)) || return 0
  info "Installing AUR packages for ${user}: ${#primary_aur[@]} packages"
  runner_aur_install "$user" "$helper" "${primary_aur[@]}"
}

# ── Config Apply pass (ADR 0134) ─────────────────────────────────────────────
# Copy each selected program's home/ into $HOME (honoring config_exclude) and
# seed the machine default into /etc/skel + /root. Runs while the staged
# programs tree still exists (before _runner_cleanup).
_runner_config_apply_pass() {
  local ships_home system_programs_json
  ships_home="$(config_apply_ships_home_list \
    "${MOUNT_ROOT}${_RUNNER_RUNTIME_DIR}/programs")"
  system_programs_json="$(printf '%s\n' \
      "${system_programs[@]+"${system_programs[@]}"}" \
    | jq -R . | jq -s -c 'map(select(length > 0))')"
  _runner_seed_selected_defaults "$ships_home" "$system_programs_json"

  # Re-apply full group memberships now that package-created groups exist.
  # Then apply per-user config, clone dotfiles, and enable user services.
  local user
  for user in "${users[@]}"; do
    runner_apply_user_groups "$user" "${USER_JSONS[$user]}"
    runner_apply_user_config "$user" "${USER_JSONS[$user]}" "$ships_home" \
      "$system_programs_json"
    runner_clone_dotfiles "$user" "$dotfiles_repo"
    # A per-user paru.conf replaces /etc/paru.conf, so it must carry the hook
    # too (ADR 0143).
    runner_wire_paru_hook "${MOUNT_ROOT}/home/${user}/.config/paru/paru.conf"
    # user_services run last — after the user's programs + dotfiles placed
    # the providing units, so a missing unit is a real error.
    runner_enable_profile_user_services "$user" "${USER_JSONS[$user]}"
  done
}

# Seed /etc/skel + /root from the host's SELECTED home-shippers only
# (host_programs ∪ every user's programs), so an unselected program never
# leaves a dangling config under /root. No config_exclude here — it is the
# machine default, shared across users.
_runner_seed_selected_defaults() {
  local ships_home="$1" system_programs_json="$2"
  local all_user_programs='[]' user_json
  for user_json in "${USER_JSONS[@]}"; do
    all_user_programs="$(jq -c -n --argjson a "$all_user_programs" \
      --argjson b "$(jq -c '.programs // []' <<<"$user_json")" '$a + $b')"
  done
  runner_seed_skeleton_root "$(config_apply_plan \
    "$(jq -c -n --argjson s "$system_programs_json" \
       --argjson u "$all_user_programs" '$s + $u')" "$ships_home" '[]')"
}
