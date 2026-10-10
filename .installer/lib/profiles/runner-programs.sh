#!/usr/bin/env bash
# =============================================================================
# lib/profiles/runner-programs.sh — the Runner's program installs
# =============================================================================
# Used by: lib/profiles/runner.sh (sources it). Runs each Host Program's
# install.sh as root and each User Program's as its user, inside the chroot.
# =============================================================================

_runner_programs_install_host_program() {
  local program="$1"
  local relative_path
  relative_path="$(resolve_program "$program")"
  info "Installing Host Program: ${program}  (.installer/programs/${relative_path})"
  arch-chroot "$MOUNT_ROOT" /usr/bin/env \
    INSTALLER_DIR="${_RUNNER_RUNTIME_DIR}" \
    PROGRAMS="${_RUNNER_RUNTIME_DIR}/programs" \
    SHELL_COMMONS="${_RUNNER_RUNTIME_DIR}/lib" \
    /usr/bin/bash "${_RUNNER_RUNTIME_DIR}/lib/profiles/program-runner.sh" \
    "${_RUNNER_RUNTIME_DIR}/programs/${relative_path}/install.sh"
}

# One chroot run of a user program's install.sh. Factored out of
# _runner_programs_install_user_program so _retry can re-invoke it: the heredoc
# feeding `bash -s` is consumed as stdin per call, so it must live in a function
# the retry loop re-enters (a heredoc on the _retry line would EOF after try
# one). Args: <user> <runtime-dir> <install-sh-path> <helper>.
_runner_programs_user_program_chroot() {
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

_runner_programs_install_user_program() {
  local user="$1" program="$2" helper="$3"
  local relative_path
  relative_path="$(resolve_program "$program")"
  info "Installing user program: ${program}  (user=${user}, .installer/programs/${relative_path})"
  # Under yay (no vetting hook, ADR 0143) the helper is repo-only: a program's
  # repo packages still install, an AUR-only one fails instead of building
  # unvetted.
  local helper; helper="$(aur_helper_repo_command "$helper")"
  # AUR_HELPER is the helper the ladder landed for this user (ADR 0052), passed
  # in from runner_run_profiles rather than re-detected here; program install.sh
  # scripts install via ${AUR_HELPER} -S. Those scripts hit
  # aur.archlinux.org/rpc too, so retry the whole run on a transient blip (ADR
  # 0052) — the scripts are idempotent (`-S --needed`, config overwrite,
  # `systemctl enable`), so a re-run after a partial pass is safe. A genuine
  # failure still aborts after last try.
  _retry 3 "5,15" -- _runner_programs_user_program_chroot \
    "$user" \
    "${_RUNNER_RUNTIME_DIR}" \
    "${_RUNNER_RUNTIME_DIR}/programs/${relative_path}/install.sh" \
    "$helper"
}

runner_install_host_programs() {
  local program
  for program in "${system_programs[@]}"; do
    _runner_programs_install_host_program "$program"
    runner_enable_system_services "$program"
  done
}

# Reconcile the reference (ADR 0036): a system:false program installs at user
# level; a Host Program the host already installs is a no-op; a Host Program
# no host installs aborts (reconcile prints why).
runner_install_user_program() {
  local user="$1" program="$2" helper="$3" action
  action="$(reconcile_user_program "$program" \
    "${system_programs[@]+"${system_programs[@]}"}")" \
    || error "User '${user}': cannot reconcile program '${program}'."
  case "$action" in
  user)
    _runner_programs_install_user_program "$user" "$program" "$helper"
    runner_enable_user_services "$user" "$program"
    ;;
  noop)
    info "User '${user}': '${program}' already installed by the host" \
         "— skipping user-level install."
    ;;
  esac
}

