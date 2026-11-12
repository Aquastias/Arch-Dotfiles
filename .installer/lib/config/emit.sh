#!/usr/bin/env bash
# =============================================================================
# lib/config/emit.sh — Guided Installer Emitter (ADR 0039)
# =============================================================================
# Turns a Config State (the sparse override map) plus an optional disk
# assignment into the device-baked **Effective Config** the back-end consumes —
# the same artifact the Pre-Install Picker produces. The override map is merged
# *over Host Core* (the neutral base — swappiness, base users — still
# applies), then the picked disks are baked onto the layout skeleton.
#
# Pure: reads INSTALLER_DIR's Host Core, no disk writes, JSON on stdout.
# Requires INSTALLER_DIR set.
#
# Public API:
#   emit_effective <state> <assignment>  → device-baked Effective Config
#
# Used by: lib/guided/save.sh, lib/guided/shell.sh, lib/matrix/assemble.sh.
# =============================================================================

# shellcheck source=../common.sh
declare -F json_string_array >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../common.sh"
# shellcheck source=./config-state.sh
declare -F config_state_emit >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config-state.sh"
# shellcheck source=./layer-resolver.sh
declare -F layer_resolver_additive_keys >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/layer-resolver.sh"
# shellcheck source=./program-registry.sh
declare -F _program_registry_parse >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/program-registry.sh"
# shellcheck source=../picker.sh
declare -F picker_assign_disks >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../picker.sh"
# shellcheck source=./printing.sh
declare -F printing_inject >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/printing.sh"
# shellcheck source=./bluetooth.sh
declare -F bluetooth_inject >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/bluetooth.sh"
# shellcheck source=./power.sh
declare -F power_inject >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/power.sh"
# shellcheck source=./mirrors.sh
declare -F mirrors_inject >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/mirrors.sh"

# emit_profile_delta <config> — the device-less Host Profile a Save writes
# (issue 08). Strips every device path — the single `.disk` and the per-pool
# `.disks[]` arrays — keeping the mode/topology/disk_count skeleton, so the
# committed artifact never carries operator-picked devices (ADR 0036's invariant)
# yet still re-installs via `install.sh --profile <name>`. Pure: JSON in/out.
emit_profile_delta() {
  local strip='del(.disk)'
  strip+=' | if .os_pool then .os_pool |= del(.disks) else . end'
  strip+=' | if .storage_groups then .storage_groups |= map(del(.disks))'
  strip+=' else . end'
  strip+=' | if .data_pools then .data_pools |= map(del(.disks)) else . end'
  # The config without its device paths.
  printf '%s\n' "$1" | jq -c "$strip"
}

# emit_core_delta <effective> <core> — the effective config reduced to what
# it adds OVER Host Core, so a saved profile stays layered rather than
# freezing a snapshot (ADR 0056, PRD story 32). The menu baseline loads Host
# Core, so the effective view holds core's whole package list, Host Programs
# and sysctl; writing that verbatim would bake them into every saved profile.
# `layer_resolver_resolve host <core> <delta>` reproduces <effective>
# (emit-core-delta.jq). Pure: JSON in, JSON out.
emit_core_delta() {
  local effective="$1" core="$2" additive program
  additive="$(layer_resolver_additive_json host)"
  program="$(layer_resolver_jq_prelude)"
  program+="$(cat "${BASH_SOURCE[0]%/*}/emit-core-delta.jq")"
  # What the effective config adds over core.
  jq -n --argjson eff "$effective" --argjson core "$core" \
    --argjson additive "$additive" "$program"
}

# emit_user_profile <form> — author a User Profile delta (issue 07) from an
# ad-hoc user form. Drops the `name` key (the directory basename is the username,
# ADR 0036) and prunes empty values (empty string, empty array, `false`, null)
# so the result is a sparse delta over User Core — only what the operator set,
# closed-schema-valid. Pure: form JSON in → profile JSON out.
emit_user_profile() {
  local prune='del(.name) | with_entries(select((.value != null)'
  prune+=' and (.value != "") and (.value != false)'
  prune+=' and (.value != []) and (.value != {})))'
  # The form without its name and its empty values.
  printf '%s\n' "$1" | jq -c "$prune"
}

# _emit_json_array <item...> — a JSON string array of the args ([] when none).
_emit_json_array() {
  (($#)) || { printf '[]'; return 0; }
  json_string_array "$@"
}

# emit_effective <state> <assignment> — Effective Config on stdout.
# Bakes the assignment's picked disks onto the layout skeleton (reusing the
# picker's assembler).
#
# Host Core is NOT merged here — it enters once, into the menu's baseline
# (config_state_seed_defaults), and the caller passes the effective view.
# Merging it again was the bug where the menu showed `host programs: grub` but
# the install produced `["cups","grub"]` (display replaced arrays, emit
# concatenated).
#
# No promotion step either: a name is either a Program or a package, enforced at
# config load by program_registry_validate_package_exclusivity (it used to be
# promoted here only in the guided path, diverging from the --profile / file
# paths).
emit_effective() {
  local state="$1" assignment="$2" view
  # Apply the operator's own exclusions before baking disks. The Packages
  # screen writes packages.exclude into Config State, but the guided path
  # never goes through a layer fold (core is already in the baseline), so
  # without this an unchecked package would be emitted and installed anyway.
  view="$(layer_resolver_apply_exclusions "$(config_state_emit "$state")")"
  # Section-derived Host Programs (ADR 0079/0080/0089): fold cups (printing),
  # bluetooth, the power daemon, then reflector (mirrors) into host_programs at
  # emit — the Printing / Bluetooth / Power / Mirrors sections own them, so they
  # are derived here, not shown as baseline entries.
  mirrors_inject "$(power_inject "$(bluetooth_inject \
    "$(printing_inject "$(picker_assign_disks "$view" "$assignment")")")")"
}
