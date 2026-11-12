#!/usr/bin/env bash
# =============================================================================
# lib/config/bluetooth.sh — Bluetooth Service resolver (ADR 0080)
# =============================================================================
# Pure core turning `options.bluetooth.enabled` into the Host Program `bluetooth`
# when on (default), nothing when off — twinning printing.sh. The program
# installs bluez + bluez-utils and enables bluetooth.service, so the daemon runs
# on first boot independent of the desktop (on KDE bluez rides plasma-meta, so
# the effect is the service enable). The GUI tray is the desktop's concern.
#
# The on/off rule lives in one place (bluetooth_enabled); *_programs + *_inject
# derive from it, never re-encoding the literal. JSON in, decision out.
#
# Public API:
#   bluetooth_enabled         <config-json> → "true" | "false" (default on)
#   bluetooth_programs        <config-json> → derived Host Programs, one/line
#   bluetooth_inject          <config-json> → config with the derived programs
#                                             folded into .host_programs
#   bluetooth_owned_programs                → every program the toggle owns,
#                                             state-independent (picker filter)
#
# Used by: lib/config/{emit,menu-owned,profile-loader}.sh,
# lib/packages/package-resolver.sh, lib/guided/controller.sh.
# =============================================================================

# shellcheck source=./derived-programs.sh
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

declare -F derived_programs_inject >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/derived-programs.sh"

# bluetooth_enabled <config-json> — "true" unless the toggle is explicitly
# false (absent ⇒ on, matching the default-on accessor). An explicit null check
# so a stored `false` round-trips rather than being read as absent.
bluetooth_enabled() {
  local enabled='(.options.bluetooth.enabled) as $v'
  enabled+=' | if $v == false then "false" else "true" end'
  # "false" only when the toggle is explicitly off.
  printf '%s\n' "${1:-{\}}" | jq -r "$enabled"
}

# bluetooth_programs <config-json> — the toggle-derived Host Programs, one per
# line: `bluetooth` when on, nothing when off. The source of truth both the
# injector and the resolver consume, so neither re-encodes the mapping.
bluetooth_programs() {
  [[ "$(bluetooth_enabled "${1:-{\}}")" == "true" ]] && printf '%s\n' bluetooth
  return 0
}

# bluetooth_inject <config-json> — the config with the toggle-derived System
# Programs folded into .host_programs (order-preserving, idempotent). A no-op
# when bluetooth yields nothing. Pure: JSON in, compact JSON out.
bluetooth_inject() {
  local config="${1:-{\}}"
  derived_programs_inject "$config" "$(bluetooth_programs "$config")"
}

# bluetooth_owned_programs — every Host Program the Bluetooth toggle owns,
# regardless of state. Filtered out of the Packages system-programs picker so
# the Bluetooth category stays its sole menu home (ADR 0080), exactly as the
# Printing toggle filters cups.
bluetooth_owned_programs() { printf '%s\n' bluetooth; }
