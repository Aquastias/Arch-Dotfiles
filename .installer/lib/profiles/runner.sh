#!/usr/bin/env bash
# =============================================================================
# lib/profiles/runner.sh — Host/user profile runner
# =============================================================================
# Sourced by 03-install.sh after configure_system().
# Requires: lib/common.sh and lib/config/layers.sh already sourced.
#
# Public API:
#   run_profiles  Entry point. Reads merged host config for $RESOLVED_HOST_PROFILE,
#                 creates users, installs Host Programs, bootstraps paru per
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

# AUR Helper resolution rule (_profiles_detect_helper), shared with
# tools/install-pkglist.sh so it has a single definition (ADR 0052).
# shellcheck source=../aur-helper.sh
declare -F _profiles_detect_helper >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../aur-helper.sh"
# shellcheck source=../config/fonts.sh
declare -F fonts_aur_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/fonts.sh"
# Config Apply Planner (ADR 0134): decides which selected programs' home/ config
# to copy for a user, honoring config_exclude. Decoupled from package install.
# shellcheck source=../config/config-apply.sh
declare -F ca_plan >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/config-apply.sh"

readonly _PROFILES_DEFAULT_PASSWORD="12345"
readonly _PROFILES_RUNTIME_DIR="/var/tmp/.installer-runtime"
readonly _PROFILES_SUDO_DROPIN="/etc/sudoers.d/01-profiles-runner"
# AUR Vetting (ADR 0143). The rungs and paru's PreBuildCommand call the
# vetter by absolute path, so nothing earlier on a user's PATH stands in.
: "${_PROFILES_AUR_VET_BIN:=/usr/local/bin/aur-vet}"
readonly -a _AUR_VET_SHARE_FILES=(
  scan.awk bump-only.awk rules.tsv indicators.tsv campaigns.tsv sources.tsv
)
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

# Generic retry-with-backoff (ADR 0052). Runs the command; on failure sleeps the
# next backoff value and retries, up to <attempts> total tries. Returns the
# command's last exit status. `attempts` counts *total* tries, so the number of
# sleeps is attempts-1; backoff is a CSV of per-gap seconds (missing → 0). The
# bootstrap ladder calls `_retry 3 "3,10"` — one initial try plus two retries,
# sleeping 3s then 10s (~13s worst case per rung).
#   _retry <attempts> <backoff-csv> -- cmd [args...]
_retry() {
  local attempts="$1" backoff_csv="$2"; shift 2
  [[ "${1:-}" == "--" ]] && shift
  local -a backoff=()
  IFS=',' read -ra backoff <<< "$backoff_csv"
  local n=0 rc=0
  while :; do
    n=$((n + 1))
    # `&& return 0 || rc=$?` captures the command's own status (an `if` around
    # it would swallow it) while staying set -e-safe.
    "$@" && return 0 || rc=$?
    (( n >= attempts )) && return "$rc"
    sleep "${backoff[n-1]:-0}"
  done
}

# Stage program tree + Shell Stdlib + program runner inside the chroot so
# install.sh scripts can run via arch-chroot with stable, predictable paths.
_profiles_stage_runtime() {
  local target="${MOUNT_ROOT}${_PROFILES_RUNTIME_DIR}"
  rm -rf "$target"
  mkdir -p "$target/lib"
  if [[ -d "${INSTALLER_DIR}/programs" ]]; then
    cp -r "${INSTALLER_DIR}/programs" "$target/programs"
  else
    mkdir -p "$target/programs"
  fi
  local f
  for f in "${_STAGED_RUNTIME_FILES[@]}"; do
    mkdir -p "$(dirname "$target/${f}")"
    cp -r "${INSTALLER_DIR}/${f}" "$target/${f}"
  done
  chmod +x "$target/lib/profiles/program-runner.sh"
  find "$target/programs" -name '*.sh' -exec chmod +x {} \;
}



# Install AUR Vetting into the target (ADR 0143): the command on PATH, its
# engine + data under /usr/local/share/aur-vet, and the root-owned pin store
# /etc/aur-vet seeded from the repo's Vetted Commits, plus the login check
# /etc/profile.d/aur-vet.sh (`aur-vet doctor`). Runs before any AUR
# Helper bootstrap, so the very first AUR build is vetted. Mandatory — not a
# Program, never toggled.
_profiles_install_aur_vet() {
  local src="${INSTALLER_DIR}/aur" root="${MOUNT_ROOT}" f
  install -Dm0755 "$src/aur-vet" "${root}${_PROFILES_AUR_VET_BIN}"
  install -d -m0755 "$root/usr/local/share/aur-vet" "$root/etc/aur-vet"
  for f in "${_AUR_VET_SHARE_FILES[@]}"; do
    install -m0644 "$src/$f" "$root/usr/local/share/aur-vet/$f"
  done
  install -m0644 "$src/vetted.tsv" "$src/allow.tsv" "$root/etc/aur-vet/"
  install -Dm0644 "$src/profile.d-aur-vet.sh" "$root/etc/profile.d/aur-vet.sh"
}

# Point paru's PreBuildCommand at the vetter in <conf> (a system or per-user
# paru.conf): drop any other PreBuildCommand, set ours under [options]. paru
# reads a user's own paru.conf *instead of* /etc/paru.conf, so each one must
# carry the hook (ADR 0143). Idempotent; a missing file is a no-op unless
# `create` is passed (the system paru.conf).
_profiles_wire_paru_hook() {
  local conf="$1" line="PreBuildCommand = ${_PROFILES_AUR_VET_BIN}"
  # `create`: the system config must exist, or paru runs unhooked.
  [[ "${2:-}" == create && ! -f "$conf" ]] && printf '[options]\n' > "$conf"
  [[ -f "$conf" ]] || return 0
  awk -v hook="$line" '
    /^[[:space:]]*#?[[:space:]]*PreBuildCommand[[:space:]]*=/ { next }
    { print }
    /^\[options\][[:space:]]*$/ && !done { print hook; done = 1 }
    END { if (!done) { print "[options]"; print hook } }' "$conf" \
    > "${conf}.new"
  cat "${conf}.new" > "$conf"
  rm -f "${conf}.new"
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

# True (0) iff install-state at <path> records a SOPS secret. Thin delegator
# to the Install State gate (the .secrets-only rule + ADR 0025 invariant live
# there, beside the keys they read). Drives implicit sops activation below.
_profiles_host_uses_secrets() {
  install_state_activates_sops "$1"
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
  # `|| return 0`, not `&& printf`: with no programs the arithmetic is false
  # (exit 1), which would trip the install's ERR trap when this feeds a
  # `mapfile < <(...)` — a host with zero host_programs is valid (empty list).
  ((${#progs[@]})) || return 0
  printf '%s\n' "${progs[@]}"
}

# Pure list-shaper for the Security & Backup Extras (M4, ADR 0041). Resolves the
# host post_install.{security,backup} object to its Program names and unions
# them into the Primary User's install list: the user's own programs first (in
# declared order), then the resolved extras not already present (resolver
# canonical order), so a tool declared in both installs once. One per line; the
# whole list empty (no output) is valid. Args: <post_install_json> [uprog...].
_profiles_resolve_post_install() {
  local pi_json="$1"; shift
  local -a out=("$@")
  local -a extras=()
  local _ex
  _ex="$(post_install_programs "$pi_json")" || return 1
  [[ -n "$_ex" ]] && mapfile -t extras <<< "$_ex"

  local e p has
  for e in "${extras[@]+"${extras[@]}"}"; do
    has=0
    for p in "${out[@]+"${out[@]}"}"; do
      [[ "$p" == "$e" ]] && { has=1; break; }
    done
    ((has)) || out+=("$e")
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
    adapter="${INSTALLER_DIR}/extras/desktop/${de}/install-${de}.jsonc"
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
  # The .secrets / .guided_passwords precedence lives in the Install State
  # module — the schema's owner — not re-encoded here.
  raw_path="$(install_state_credential_path "$host_state" user "$name")"
  [[ -n "$raw_path" && -f "$raw_path" ]] || return 0
  local chroot_dir="${MOUNT_ROOT}${_PROFILES_RUNTIME_DIR}/secrets"
  mkdir -p "$chroot_dir"
  cp "$raw_path" "${chroot_dir}/${name}-secrets.json"
  printf '%s' "${_PROFILES_RUNTIME_DIR}/secrets/${name}-secrets.json"
}

_profiles_create_user() {
  local name="$1" json="$2" fullname="${3:-}"
  local shell sudo_flag groups_csv
  shell="$(printf '%s' "$json" | jq -r '.shell // "/bin/bash"')"
  sudo_flag="$(printf '%s' "$json" | jq -r '.sudo // false')"
  groups_csv="$(resolve_user_groups "$json")"
  info "Creating user: ${name}" \
       "(shell=${shell}, sudo=${sudo_flag}, groups=${groups_csv:-<none>})"
  local sec_path
  sec_path="$(_profiles_resolve_user_secrets "$name")"
  # Primary User display name → GECOS (ADR 0121). Passed as a chroot env var
  # (arch-chroot strips the host env, and adding a positional arg would collide
  # with the optional secrets path); create-user.sh reads USER_FULLNAME. An
  # array so a name with spaces stays one token; empty ⇒ no env prefix.
  local -a env_pfx=()
  [[ -n "$fullname" ]] && env_pfx=(env "USER_FULLNAME=$fullname")
  arch-chroot "$MOUNT_ROOT" "${env_pfx[@]}" \
    /usr/bin/bash /root/lib-chroot/create-user.sh \
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

_profiles_install_host_program() {
  local prog="$1"
  local rel
  rel="$(resolve_program "$prog")"
  info "Installing Host Program: ${prog}  (.installer/programs/${rel})"
  arch-chroot "$MOUNT_ROOT" /usr/bin/env \
    INSTALLER_DIR="${_PROFILES_RUNTIME_DIR}" \
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

# Probe the AUR Helper already installed for <user> inside the chroot. Prints
# `paru`/`yay` (paru preferred) and returns 0 when one exists; non-zero and no
# output when neither does. The in-chroot mirror of _profiles_detect_helper.
_profiles_detect_user_helper() {
  local user="$1"
  # shellcheck disable=SC2016  # $h is expanded by the chroot's shell, not here.
  arch-chroot "$MOUNT_ROOT" su - "$user" -c '
    for h in paru yay; do
      if command -v "$h" >/dev/null 2>&1; then echo "$h"; exit 0; fi
    done
    exit 1'
}

# One rung of the bootstrap ladder: build+install <aur-pkg> as <user> in the
# chroot via git clone + AUR Vetting + makepkg. The helper package is the
# first AUR build, so it is vetted like any other (ADR 0143); the full clone
# lets a newer HEAD be diffed against its Vetted Commit. Returns the rung's
# status. Wrapped in _retry by the ladder and stubbed in unit tests.
_profiles_bootstrap_rung() {
  local user="$1" pkg="$2"
  arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- "$user" "$pkg" \
    "$_PROFILES_AUR_VET_BIN" <<'CHROOT_RUNG'
set -e
USER_NAME="$1"; PKG="$2"; VET="$3"
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
BUILD="${HOME_DIR}/.aur-helper-bootstrap"
rm -rf "$BUILD"
su - "$USER_NAME" -c "
  set -e
  git clone https://aur.archlinux.org/${PKG}.git '${BUILD}'
  cd '${BUILD}'
  AUR_VET_UNATTENDED=1 PKGBASE='${PKG}' '${VET}'
  makepkg -si --noconfirm
"
rm -rf "$BUILD"
CHROOT_RUNG
}

# Bootstrap an AUR Helper for <user> via the resilience ladder (ADR 0052):
# `paru` source → `paru-bin` → `yay-bin`, each shallow-retried before dropping
# to the next (different) endpoint. Prints the landed helper's name (`paru`/`yay`)
# on stdout; logs go to stderr so the name is cleanly capturable. Skips when the
# user already has a helper. Aborts the install only if every rung fails.
_profiles_bootstrap_helper() {
  local user="$1"
  local existing
  if existing="$(_profiles_detect_user_helper "$user")"; then
    info "AUR helper already present for ${user}: ${existing}" >&2
    printf '%s\n' "$existing"
    return 0
  fi
  info "Bootstrapping AUR helper for user: ${user}" >&2
  local pkg landed
  for pkg in "${_AUR_HELPER_LADDER[@]}"; do
    # Rung stdout (git clone + makepkg build log) → stderr, so it stays visible
    # on the terminal but never contaminates this function's stdout, which
    # carries only the resolved helper name for the caller's capture.
    if _retry 3 "3,10" -- _profiles_bootstrap_rung "$user" "$pkg" >&2; then
      case "$pkg" in
        yay-bin) landed=yay ;;
        *)       landed=paru ;;
      esac
      info "AUR helper bootstrapped via ${pkg} (${landed}) for ${user}" >&2
      printf '%s\n' "$landed"
      return 0
    fi
    warn "AUR-helper rung '${pkg}' failed for ${user}; trying next rung." >&2
  done
  error "All AUR-helper bootstrap rungs failed for ${user}" \
        "(paru, paru-bin, yay-bin) — upstream AUR/GitHub may be unavailable."
}

# Resolve + install an AUR set for a user with their <helper>. AUR builds
# need paru: its PreBuildCommand runs AUR Vetting per package base, and yay
# has no such hook, so the yay fallback rung refuses here (ADR 0143). A
# print-only pre-flight pass runs first in the real installed environment,
# so a provider/conflict failure — a virtual dep (e.g. libjpeg6) whose
# default provider conflicts with an already installed package — aborts
# *before* any download, with an actionable hint, instead of the bare ERR-trap
# line number. The real install streams live, the hook unattended.
_profiles_aur_install() {
  local user="$1" helper="$2"; shift 2
  local -a pkgs=("$@")
  ((${#pkgs[@]} > 0)) || return 0
  _aur_helper_vets_aur "$helper" \
    || error "AUR install for ${user} landed on ${helper}: vetting needs paru" \
             "(ADR 0143) — retry once the paru rung can bootstrap."

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
    # Non-conflict failure (e.g. transient resolver hiccup): warn, let the
    # real pass surface it through the normal ERR trap.
    warn "AUR pre-flight returned non-zero with no conflict signature;" \
         "proceeding to install."
    printf '%s\n' "$out" >&2
  fi

  # The real install hits aur.archlinux.org/rpc to resolve deps; a transient
  # RPC/network blip there must not abort the whole install (ADR 0052). Retry
  # with backoff — --needed keeps it idempotent, so a re-run skips what landed.
  # A genuine build/conflict failure still aborts after the last try.
  _retry 3 "5,15" -- arch-chroot "$MOUNT_ROOT" su - "$user" -c \
    "AUR_VET_UNATTENDED=1 paru -S --noconfirm --needed ${pkgs[*]}"
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

# One chroot run of a user program's install.sh. Factored out of
# _profiles_install_user_program so _retry can re-invoke it: the heredoc feeding
# `bash -s` is consumed as stdin per call, so it must live in a function the
# retry loop re-enters (a heredoc on the _retry line would EOF after try one).
# Args: <user> <runtime-dir> <install-sh-path> <helper>.
_profiles_userprog_chroot() {
  arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- \
    "$1" "$2" "$3" "$4" <<'CHROOT_USERPROG'
set -e
USER_NAME="$1"; OS_DIR_IN="$2"; INSTALL_SH="$3"; AUR_HELPER_IN="$4"
su - "$USER_NAME" -c "
  export INSTALLER_DIR='${OS_DIR_IN}'
  export PROGRAMS='${OS_DIR_IN}/programs'
  export SHELL_COMMONS='${OS_DIR_IN}/lib'
  export AUR_HELPER='${AUR_HELPER_IN}'
  export AUR_VET_UNATTENDED=1
  bash '${OS_DIR_IN}/lib/profiles/program-runner.sh' '${INSTALL_SH}'
"
CHROOT_USERPROG
}

_profiles_install_user_program() {
  local user="$1" prog="$2" helper="$3"
  local rel
  rel="$(resolve_program "$prog")"
  info "Installing user program: ${prog}  (user=${user}, .installer/programs/${rel})"
  # Under yay (no vetting hook, ADR 0143) the helper is repo-only: a program's
  # repo packages still install, an AUR-only one fails instead of building
  # unvetted.
  local h; h="$(_aur_helper_repo_cmd "$helper")"
  # AUR_HELPER is the helper the ladder landed for this user (ADR 0052), passed
  # in from run_profiles rather than re-detected here; program install.sh
  # scripts install via ${AUR_HELPER} -S. Those scripts hit aur.archlinux.org/rpc
  # too, so retry the whole run on a transient blip (ADR 0052) — the scripts are
  # idempotent (`-S --needed`, config overwrite, `systemctl enable`), so a re-run
  # after a partial pass is safe. A genuine failure still aborts after last try.
  _retry 3 "5,15" -- _profiles_userprog_chroot \
    "$user" \
    "${_PROFILES_RUNTIME_DIR}" \
    "${_PROFILES_RUNTIME_DIR}/programs/${rel}/install.sh" \
    "$h"
}


_profiles_write_authorized_keys() {
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
  # "cannot stat". Args cross the chroot boundary with no shared-path assumption.
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

_profiles_enable_system_services() {
  local prog="$1"
  local rel config_file
  rel="$(resolve_program "$prog")"
  config_file="${INSTALLER_DIR}/programs/${rel}/config.jsonc"
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
  config_file="${INSTALLER_DIR}/programs/${rel}/config.jsonc"
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
# ADR 0134: config is applied by the Config Apply pass from the staged tree;
# the installer never stows (ADR 0095). The operator runs ./stow-configs.sh on
# their installed system for live symlinks. This path just places the repo.
CLONE_INNER
# mktemp created the script as root (0600); make it readable so the su'd user
# can run it — otherwise "bash: <tmp>: Permission denied" aborts the install.
# Only reachable once a host sets dotfiles_repo (the VM path exercises it).
chmod 0644 "$CLONE_SCRIPT"
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
# CONFIG APPLY PASS (ADR 0134)
# =============================================================================
# Config is decoupled from package install: install.sh installs the package,
# this pass copies each selected program's home/ tree into the user's $HOME
# (honoring config_exclude) and seeds the machine default into /etc/skel +
# /root. It is a COPY, not a stow — the staged programs tree is ephemeral
# (cleaned up post-install), so symlinks would dangle. `./stow-configs.sh` is the
# operator's day-2 symlink from the persistent clone; both read the one source.

# _profiles_names_to_rels <names-json> — map a JSON array of program names to
# their "<cat>/<name>" rel paths (one per line), skipping any that do not
# resolve. Shared by the plan and the skel/root seed so the walk lives once.
_profiles_names_to_rels() {
  local name rel
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    rel="$(resolve_program "$name" 2>/dev/null)" || continue
    printf '%s\n' "$rel"
  done < <(jq -r '.[]' <<<"$1")
}

# _profiles_config_plan_rels <user-json> <ships-home-json> <sys-progs-json>
#   → the ordered "<cat>/<name>" rel paths whose home/ config applies for this
#   user: (user programs ∪ host programs) that ship a home/ and are not in the
#   user's config_exclude. Pure planning delegated to ca_plan.
_profiles_config_plan_rels() {
  local user_json="$1" ships="$2" sysprogs="$3"
  local selected exclude plan
  selected="$(jq -c -n \
    --argjson u "$(jq -c '.programs // []' <<<"$user_json")" \
    --argjson s "$sysprogs" '$s + $u')"
  exclude="$(jq -c '.config_exclude // []' <<<"$user_json")"
  plan="$(ca_plan "$selected" "$ships" "$exclude")"
  _profiles_names_to_rels "$plan"
}

# _profiles_seed_skel_root <selected-home-json> — copy the config of each
# home/-shipping program SELECTED on this host into /etc/skel and /root (the
# machine default, ADR 0095). Scoped to the host's selection (not the whole
# catalog) so a program no user installs never leaves a dangling config under
# /root; not config_exclude-aware, since skel/root is the shared fallback for
# later-created users and for root, which never receives /etc/skel.
_profiles_seed_skel_root() {
  local selected="$1"
  local -a rels=()
  mapfile -t rels < <(_profiles_names_to_rels "$selected")
  ((${#rels[@]})) || return 0
  info "Config Apply: seeding /etc/skel + /root from ${#rels[@]} home/ tree(s)"
  arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- \
    "$_PROFILES_RUNTIME_DIR" "${rels[@]}" <<'CHROOT_SKEL'
set -e
RT="$1"; shift
mkdir -p /etc/skel
for rel in "$@"; do
  src="${RT}/programs/${rel}/home"
  [ -d "$src" ] || continue
  cp -a "${src}/." /etc/skel/
  cp -a "${src}/." /root/
done
chown -R root:root /root
CHROOT_SKEL
}

# _profiles_apply_user_config <user> <user-json> <ships-json> <sys-progs-json>
#   Copy the user's planned home/ trees into their $HOME, then chown to them
#   (cp -a from the root-owned staged tree would otherwise land root-owned).
_profiles_apply_user_config() {
  local user="$1" user_json="$2" ships="$3" sysprogs="$4"
  local -a rels=()
  mapfile -t rels < <(_profiles_config_plan_rels "$user_json" "$ships" \
    "$sysprogs")
  ((${#rels[@]})) || { info "User '${user}': no home/ config to apply."; \
    return 0; }
  info "User '${user}': applying ${#rels[@]} program config tree(s) to \$HOME"
  arch-chroot "$MOUNT_ROOT" /usr/bin/bash -s -- \
    "$user" "$_PROFILES_RUNTIME_DIR" "${rels[@]}" <<'CHROOT_APPLYCFG'
set -e
USER_NAME="$1"; RT="$2"; shift 2
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
for rel in "$@"; do
  src="${RT}/programs/${rel}/home"
  [ -d "$src" ] || continue
  cp -a "${src}/." "${HOME_DIR}/"
done
chown -R "${USER_NAME}:${USER_NAME}" "${HOME_DIR}"
CHROOT_APPLYCFG
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

  # INSTALLER_DIR is consumed by configs.sh and exported so program install.sh
  # scripts can locate the staged runtime tree.
  export INSTALLER_DIR="${SCRIPT_DIR}"

  if [[ ! -f "${INSTALLER_DIR}/hosts/core/profile.jsonc" ]]; then
    warn "Hosts core profile not found at" \
         "${INSTALLER_DIR}/hosts/core/profile.jsonc — skipping profiles runner."
    return 0
  fi
  if [[ ! -f "${INSTALLER_DIR}/users/core/profile.jsonc" ]]; then
    warn "Users core profile not found at" \
         "${INSTALLER_DIR}/users/core/profile.jsonc — skipping profiles runner."
    return 0
  fi

  # ADR 0036: read the host's software (users / host_programs / sysctl /
  # packages) from the assembled effective config — the single source of truth
  # the front-end produced (install.sh --profile or the VM seed). CONFIG_FILE
  # is set by 03-install.sh.
  local host_json
  # shellcheck disable=SC2153  # CONFIG_FILE global, set by 03-install.sh
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
    | jq -r '.host_programs[]?')

  # Implicit sops activation (ADR 0025): sops is not declared in any host
  # config; the Runner selects it through the normal system-program path
  # only when install-state records secrets, deduped against declarations.
  local _sec_active=0
  if _profiles_host_uses_secrets "${MOUNT_ROOT}/install-state.json"; then
    _sec_active=1
  fi
  mapfile -t sys_progs < <(_profiles_sops_selection "$_sec_active" \
    "${sys_progs[@]+"${sys_progs[@]}"}")

  # Pre-load user profiles for install execution.
  # Program contract validation was done by validate_install_context.
  declare -A USER_JSONS=()
  local u
  for u in "${users[@]}"; do
    local uj urc=0
    uj="$(load_user_profile "$u" 2>/dev/null)" || urc=$?
    case "$urc" in
    0 | 1) USER_JSONS["$u"]="$uj" ;;
    2) error "Users core profile could not be loaded." ;;
    3) error "User '${u}' is named 'core' (reserved)." ;;
    *) error "Unexpected return code ${urc} from" \
             "load_user_profile for '${u}'." ;;
    esac
  done

  local dotfiles_repo
  dotfiles_repo="$(install_config_dotfiles_repo)"

  # ── Stage runtime, validate it, create users, install programs ───────────
  _profiles_stage_runtime
  validate_staging "${MOUNT_ROOT}${_PROFILES_RUNTIME_DIR}"
  _profiles_install_aur_vet

  # The Primary User (first in the list) gets the display name; the rest do not
  # (ADR 0121 — avatar/name is scoped to the Primary User).
  local _primary_fullname _uidx=0
  _primary_fullname="$(install_config_fullname)"
  for u in "${users[@]}"; do
    if [[ $_uidx -eq 0 ]]; then
      _profiles_create_user "$u" "${USER_JSONS[$u]}" "$_primary_fullname"
    else
      _profiles_create_user "$u" "${USER_JSONS[$u]}"
    fi
    _profiles_write_authorized_keys "$u" "${USER_JSONS[$u]}"
    _uidx=$((_uidx + 1))
  done

  local prog
  for prog in "${sys_progs[@]}"; do
    _profiles_install_host_program "$prog"
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

  # Font Catalog (ADR 0080): AUR fonts (today ttf-ms-fonts) ride the paru pass
  # too — options.fonts is the single font home, so its AUR members union in
  # here rather than living in packages.aur. Kept out of _profiles_resolve_aur
  # (whose contract is host ∪ adapters) so that resolver stays font-agnostic.
  # Absent options.fonts ⇒ the catalog defaults.
  local _fonts_aur
  _fonts_aur="$(fonts_aur_packages "$host_json")" || return 1
  [[ -n "$_fonts_aur" ]] && mapfile -t -O "${#host_aur[@]}" host_aur \
    <<< "$_fonts_aur"

  # Security & Backup Extras (M4, ADR 0041): the host's structured
  # post_install.{security,backup} selection installs via the Primary User's
  # paru pass, deduped against that user's own programs.
  local _pi_json
  _pi_json="$(printf '%s' "$host_json" | jq -c '.post_install // {}')"

  for u in "${users[@]}"; do
    local -a uprogs=()
    mapfile -t uprogs < <(printf '%s' "${USER_JSONS[$u]}" \
      | jq -r '.programs[]?')

    # The Primary User also installs the host Security & Backup Extras; a tool
    # declared in both their programs and the selection installs once.
    if [[ "${u}" == "${users[0]}" ]]; then
      mapfile -t uprogs < <(_profiles_resolve_post_install "$_pi_json" \
        "${uprogs[@]+"${uprogs[@]}"}")
    fi

    # Bootstrap paru for this user if they have programs, or if they are the
    # primary user and there are host/GPU AUR packages to install.
    local needs_paru=0
    ((${#uprogs[@]} > 0)) && needs_paru=1
    [[ "${u}" == "${users[0]}" ]] \
      && ((${#host_aur[@]} + ${#GPU_PARU_PACKAGES[@]} > 0)) \
      && needs_paru=1
    ((needs_paru)) || continue

    _profiles_grant_temp_sudo "$u"
    local _helper
    _helper="$(_profiles_bootstrap_helper "$u")"
    [[ "$_helper" == paru ]] \
      && _profiles_wire_paru_hook "${MOUNT_ROOT}/etc/paru.conf" create
    # Install host AUR packages and GPU AUR packages for the primary user.
    if [[ "${u}" == "${users[0]}" ]]; then
      local -a primary_aur=(
        "${host_aur[@]+"${host_aur[@]}"}"
        "${GPU_PARU_PACKAGES[@]+"${GPU_PARU_PACKAGES[@]}"}"
      )
      if ((${#primary_aur[@]} > 0)); then
        info "Installing AUR packages for ${u}: ${#primary_aur[@]} packages"
        _profiles_aur_install "$u" "$_helper" "${primary_aur[@]}"
      fi
    fi
    for prog in "${uprogs[@]}"; do
      # Reconcile the reference (ADR 0036): a system:false program installs
      # at user level; a Host Program the host already installs is a no-op;
      # a Host Program no host installs aborts (reconcile prints why).
      local _action
      _action="$(reconcile_user_program "$prog" \
        "${sys_progs[@]+"${sys_progs[@]}"}")" \
        || error "User '${u}': cannot reconcile program '${prog}'."
      case "$_action" in
      user)
        _profiles_install_user_program "$u" "$prog" "$_helper"
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

  # ── Config Apply pass (ADR 0134) ─────────────────────────────────────────
  # Copy each selected program's home/ into $HOME (honoring config_exclude) and
  # seed the machine default into /etc/skel + /root. Runs while the staged
  # programs tree still exists (before _profiles_cleanup).
  local _ships_home _sysprogs_json
  _ships_home="$(ca_ships_home_list \
    "${MOUNT_ROOT}${_PROFILES_RUNTIME_DIR}/programs")"
  _sysprogs_json="$(printf '%s\n' "${sys_progs[@]+"${sys_progs[@]}"}" \
    | jq -R . | jq -s -c 'map(select(length > 0))')"
  # Seed /etc/skel + /root from the host's SELECTED home-shippers only
  # (host_programs ∪ every user's programs), so an unselected program never
  # leaves a dangling config under /root. No config_exclude here — it is the
  # machine default, shared across users.
  local _all_user_progs='[]' _uj _skel_plan
  for _uj in "${USER_JSONS[@]}"; do
    _all_user_progs="$(jq -c -n --argjson a "$_all_user_progs" \
      --argjson b "$(jq -c '.programs // []' <<<"$_uj")" '$a + $b')"
  done
  _skel_plan="$(ca_plan \
    "$(jq -c -n --argjson s "$_sysprogs_json" --argjson u "$_all_user_progs" \
      '$s + $u')" "$_ships_home" '[]')"
  _profiles_seed_skel_root "$_skel_plan"

  # Re-apply full group memberships now that package-created groups exist.
  # Then apply per-user config, clone dotfiles, and enable user services.
  for u in "${users[@]}"; do
    _profiles_apply_user_groups "$u" "${USER_JSONS[$u]}"
    _profiles_apply_user_config "$u" "${USER_JSONS[$u]}" "$_ships_home" \
      "$_sysprogs_json"
    _profiles_clone_dotfiles "$u" "$dotfiles_repo"
    # A per-user paru.conf replaces /etc/paru.conf, so it must carry the hook
    # too (ADR 0143).
    _profiles_wire_paru_hook "${MOUNT_ROOT}/home/${u}/.config/paru/paru.conf"
    # user_services run last — after the user's programs + dotfiles placed
    # the providing units, so a missing unit is a real error.
    _profiles_enable_profile_user_services "$u" "${USER_JSONS[$u]}"
  done

  _profiles_cleanup
  info "Profiles runner complete."
}
