#!/usr/bin/env bash
# =============================================================================
# lib/config/emit.sh — Guided Installer Emitter (ADR 0039)
# =============================================================================
# Turns a Config State (the sparse override map) plus an optional disk
# assignment into the device-baked **Effective Config** the back-end consumes —
# the same artifact the Pre-Install Picker produces. The override map is merged
# *over Host Core* (so the shared base — cups, swappiness, base users — still
# applies), then the picked disks are baked onto the layout skeleton.
#
# Pure: reads OS_DIR's Host Core, no disk writes, JSON on stdout.
# Requires OS_DIR set.
#
# Public API:
#   emit_effective <state> <assignment>  → device-baked Effective Config
# =============================================================================

# shellcheck source=./state.sh
[[ "$(type -t cfgstate_emit)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/state.sh"
# shellcheck source=./layers.sh
[[ "$(type -t _configs_merge)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/layers.sh"
# shellcheck source=../picker.sh
[[ "$(type -t picker_assign_disks)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/../picker.sh"

# guided_profile_delta <config> — the device-less Host Profile a Save writes
# (issue 08). Strips every device path — the single `.disk` and the per-pool
# `.disks[]` arrays — keeping the mode/topology/disk_count skeleton, so the
# committed artifact never carries operator-picked devices (ADR 0036's invariant)
# yet still re-installs via `install.sh --profile <name>`. Pure: JSON in/out.
guided_profile_delta() {
  jq -c '
    del(.disk)
    | if .os_pool then .os_pool |= del(.disks) else . end
    | if .storage_groups then .storage_groups |= map(del(.disks)) else . end
    | if .data_pools then .data_pools |= map(del(.disks)) else . end
  ' <<<"$1"
}

# guided_user_profile <form> — author a User Profile delta (issue 07) from an
# ad-hoc user form. Drops the `name` key (the directory basename is the username,
# ADR 0036) and prunes empty values (empty string, empty array, `false`, null)
# so the result is a sparse delta over User Core — only what the operator set,
# closed-schema-valid. Pure: form JSON in → profile JSON out.
guided_user_profile() {
  jq -c '
    del(.name)
    | with_entries(select(
        (.value != null) and (.value != "") and (.value != false)
        and (.value != []) and (.value != {})))
  ' <<<"$1"
}

# _emit_json_array <item...> — a JSON string array of the args ([] when none).
_emit_json_array() {
  (($#)) || { printf '[]'; return 0; }
  printf '%s\n' "$@" | jq -R . | jq -s -c .
}

# emit_effective <state> <assignment> — Effective Config on stdout.
# Merges the state's override map over Host Core, then bakes the assignment's
# picked disks onto the layout skeleton (reusing the picker's assembler).
#
# There is no promotion step. It used to run HERE and only here, so a typed
# package name resolving to a Program became a system_program in the guided
# path while `install.sh --profile` and `install.sh <config-file>` left it a
# raw package — the same file installing differently per front-end. A name is
# now either a Program or a package, enforced at config load by
# validate_package_program_exclusivity, and the guided extra-packages row
# routes what the operator types at ENTRY time (see _ctl_route_package_entry),
# so what reaches Config State is already canonical.
emit_effective() {
  local state="$1" assignment="$2" overrides core merged
  overrides="$(cfgstate_emit "$state")"
  core="$(_configs_parse "$OS_DIR/hosts/core/profile.jsonc")" || core='{}'
  merged="$(_configs_merge "$core" "$overrides")"
  picker_assign_disks "$merged" "$assignment"
}
