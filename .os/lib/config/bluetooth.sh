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
# =============================================================================

# bluetooth_enabled <config-json> — "true" unless the toggle is explicitly
# false (absent ⇒ on, matching the default-on accessor). An explicit null check
# so a stored `false` round-trips rather than being read as absent.
bluetooth_enabled() {
  jq -r '(.options.bluetooth.enabled) as $v
    | if $v == false then "false" else "true" end' <<<"${1:-{\}}"
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
  local cfg="${1:-{\}}" progs
  progs="$(bluetooth_programs "$cfg")"
  [[ -n "$progs" ]] || { jq -c . <<<"$cfg"; return; }
  jq -c --arg progs "$progs" '
    ($progs | split("\n") | map(select(length > 0))) as $add
    | .host_programs = ((.host_programs // []) as $sp
        | reduce $add[] as $p ($sp;
            if (. | index($p)) then . else . + [$p] end))
  ' <<<"$cfg"
}

# bluetooth_owned_programs — every Host Program the Bluetooth toggle owns,
# regardless of state. Filtered out of the Packages system-programs picker so
# the Bluetooth category stays its sole menu home (ADR 0080), exactly as the
# Printing toggle filters cups.
bluetooth_owned_programs() { printf '%s\n' bluetooth; }
