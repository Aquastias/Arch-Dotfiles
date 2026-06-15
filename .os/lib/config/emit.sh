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

# emit_effective <state> <assignment> — Effective Config on stdout.
# Merges the state's override map over Host Core, then bakes the assignment's
# picked disks onto the layout skeleton (reusing the picker's assembler).
emit_effective() {
  local state="$1" assignment="$2" overrides core merged
  overrides="$(cfgstate_emit "$state")"
  core="$(_configs_parse "$OS_DIR/hosts/core/profile.jsonc")" || core='{}'
  merged="$(_configs_merge "$core" "$overrides")"
  picker_assign_disks "$merged" "$assignment"
}
