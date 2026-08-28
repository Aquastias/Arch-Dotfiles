#!/usr/bin/env bash
# =============================================================================
# lib/guided-save.sh — Guided Installer terminal-action writers (issue 08)
# =============================================================================
# The two non-Proceed terminal actions, as testable file writers:
#
#   guided_save_host_profile <state> <name>  — write a device-LESS Host Profile
#       delta over Host Core to hosts/<name>/profile.jsonc (re-installs via
#       `install.sh --profile <name>`). Refuses to overwrite an existing
#       hosts/<name>/ — there is no overwrite path; the operator picks a new
#       name. Disks are stripped (guided_profile_delta); the committed audit
#       artifact never carries operator-picked devices (ADR 0036).
#
#   guided_export_config <effective> <path>  — write the device-BAKED Effective
#       Config to an operator path (re-installs via `install.sh <config-file>`),
#       refusing any path under the repo's hosts/ tree (that is Save's job; the
#       export deliberately keeps device paths out of committed source).
#
# Pure deps only (state / emit / profile) — no fzf, no disk ops beyond the
# single profile/config write. Requires INSTALLER_DIR set.
# =============================================================================

# shellcheck source=./config/state.sh
declare -F cfgstate_emit >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config/state.sh"
# shellcheck source=./config/emit.sh
declare -F guided_profile_delta >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config/emit.sh"
# shellcheck source=./config/seed.sh
declare -F cfgstate_host_core >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config/seed.sh"
# shellcheck source=./config/profile.sh
declare -F validate_config_schema >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config/profile.sh"

# guided_save_host_profile <state> <name> — see header. rc 1 (no write) on an
# empty name, a name collision, or a schema-invalid delta.
guided_save_host_profile() {
  local state="$1" name="$2"
  [[ -n "$name" ]] || { error "guided: Save needs a profile name"; return 1; }
  local dir="${INSTALLER_DIR}/hosts/${name}"
  if [[ -e "${dir}/profile.jsonc" ]]; then
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
  delta="$(guided_profile_delta "$(cfgstate_emit "$state")")"
  delta="$(guided_core_delta "$delta" "$(cfgstate_host_core)")"
  validate_config_schema host "$delta" || return 1
  mkdir -p "$dir"
  printf '%s\n' "$delta" > "${dir}/profile.jsonc"
}

# guided_export_config <effective> <path> — see header. rc 1 (no write) on an
# empty path or a path under hosts/.
guided_export_config() {
  local effective="$1" path="$2"
  [[ -n "$path" ]] || { error "guided: Export needs a path"; return 1; }
  local abs hosts_abs
  abs="$(realpath -m "$path")"
  hosts_abs="$(realpath -m "${INSTALLER_DIR}/hosts")"
  case "$abs" in
  "$hosts_abs" | "$hosts_abs"/*)
    error "guided: Export must not write under hosts/ — that is Save's job." \
          "Pick a path outside the repo (e.g. a USB)."
    return 1
    ;;
  esac
  mkdir -p "$(dirname "$abs")"
  printf '%s\n' "$effective" > "$abs"
}
