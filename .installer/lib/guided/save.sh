#!/usr/bin/env bash
# =============================================================================
# lib/guided/save.sh — Guided Installer terminal-action writers (issue 08)
# =============================================================================
# The two non-Proceed terminal actions, as testable file writers:
#
#   guided_save_host_profile <state> <name>  — write a device-LESS Host Profile
#       delta over Host Core to hosts/<name>/profile.jsonc (re-installs via
#       `install.sh --profile <name>`). Refuses to overwrite an existing
#       hosts/<name>/ — there is no overwrite path; the operator picks a new
#       name. Disks are stripped (emit_profile_delta); the committed audit
#       artifact never carries operator-picked devices (ADR 0036).
#
#   guided_export_config <effective> <path>  — write the device-BAKED Effective
#       Config to an operator path (re-installs via `install.sh <config-file>`),
#       refusing any path under the repo's hosts/ tree (that is Save's job; the
#       export deliberately keeps device paths out of committed source).
#
# Pure deps only (state / emit / profile) — no fzf, no disk ops beyond the
# single profile/config write. Requires INSTALLER_DIR set.
#
# Used by: lib/guided/shell.sh.
# =============================================================================

# shellcheck source=../config/config-state.sh
declare -F config_state_emit >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/config-state.sh"
# shellcheck source=../config/emit.sh
declare -F emit_profile_delta >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/emit.sh"
# shellcheck source=../config/profile-loader.sh
declare -F profile_loader_validate_schema >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/profile-loader.sh"

# guided_save_host_profile <state> <name> — see header. rc 1 (no write) on an
# empty name, a name collision, or a schema-invalid delta.
guided_save_host_profile() {
  local state="$1" name="$2"
  [[ -n "$name" ]] || { error "guided: Save needs a profile name"; return 1; }
  local directory="${INSTALLER_DIR}/hosts/${name}"
  if [[ -e "${directory}/profile.jsonc" ]]; then
    error "guided: hosts/${name}/ already exists — choose a new name" \
          "(Save never overwrites a committed profile)."
    return 1
  fi
  # Two reductions, in order: strip device paths (the committed artifact is
  # device-less, ADR 0036), then subtract Host Core so the saved profile is a
  # DELTA and stays layered (ADR 0056). Without the second, every save would
  # bake core's whole inherited package list into the new profile and decouple
  # it from core on the next edit.
  local delta
  delta="$(emit_profile_delta "$(config_state_emit "$state")")"
  delta="$(emit_core_delta "$delta" "$(config_state_host_core)")"
  profile_loader_validate_schema host "$delta" || return 1
  mkdir -p "$directory"
  printf '%s\n' "$delta" > "${directory}/profile.jsonc"
}

# guided_export_config <effective> <path> — see header. rc 1 (no write) on an
# empty path or a path under hosts/.
guided_export_config() {
  local effective="$1" path="$2"
  [[ -n "$path" ]] || { error "guided: Export needs a path"; return 1; }
  local absolute_path hosts_path
  absolute_path="$(readlink -m "$path")"
  hosts_path="$(readlink -m "${INSTALLER_DIR}/hosts")"
  case "$absolute_path" in
  "$hosts_path" | "$hosts_path"/*)
    error "guided: Export must not write under hosts/ — that is Save's job." \
          "Pick a path outside the repo (e.g. a USB)."
    return 1
    ;;
  esac
  local parent="${absolute_path%/*}"
  mkdir -p "${parent:-/}"
  printf '%s\n' "$effective" > "$absolute_path"
}
