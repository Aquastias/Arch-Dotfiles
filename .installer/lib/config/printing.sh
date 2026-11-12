#!/usr/bin/env bash
# =============================================================================
# lib/config/printing.sh — Printing Service resolver (ADR 0079)
# =============================================================================
# Pure core turning a host's `options.printing.enabled` toggle into the
# toggle-derived Host Programs: `cups` when on (the default), nothing when
# off. The single source of truth shared by the Effective-Config injector
# (emit.sh / profile.sh assembly) and the Package Resolver, so the two can
# never drift. No TTY, no disk writes — JSON in, decision out. Mirrors
# post-install.sh.
#
# cups is NOT declared in Host Core (ADR 0079); it is the first toggle-derived
# Host Program, genuinely absent when off. The toggle defaults ON to preserve
# the historical "cups on every host" behaviour. The on/off rule lives in one
# place (printing_enabled); printing_programs + printing_inject derive from it,
# so the `cups` literal is never re-encoded per consumer.
#
# Public API:
#   printing_enabled          <config-json> → "true" | "false" (default on)
#   printing_programs         <config-json> → derived Host Programs, one/line
#   printing_inject           <config-json> → config with the derived programs
#                                             folded into .host_programs
#   printing_owned_programs                 → every program the toggle owns,
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

# printing_enabled <config-json> — "true" unless the toggle is explicitly
# false (absent ⇒ on, matching the default-on accessor). The sole on/off rule;
# every other function derives from it. An explicit null check so a stored
# `false` round-trips rather than being read as absent.
printing_enabled() {
  local enabled='(.options.printing.enabled) as $v'
  enabled+=' | if $v == false then "false" else "true" end'
  # "false" only when the toggle is explicitly off.
  printf '%s\n' "${1:-{\}}" | jq -r "$enabled"
}

# printing_programs <config-json> — the toggle-derived Host Programs, one per
# line: `cups` when printing is on, nothing when off. The source of truth both
# the injector and the resolver consume, so neither re-encodes the mapping.
printing_programs() {
  [[ "$(printing_enabled "${1:-{\}}")" == "true" ]] && printf '%s\n' cups
  return 0
}

# printing_inject <config-json> — the config with the toggle-derived System
# Programs (printing_programs) folded into .host_programs (order-preserving,
# idempotent), so the Runner installs cups exactly as an authored Host Program
# when printing is on. A no-op when printing yields nothing. Pure: JSON in,
# compact JSON out.
printing_inject() {
  local config="${1:-{\}}"
  derived_programs_inject "$config" "$(printing_programs "$config")"
}

# printing_owned_programs — every Host Program the Printing toggle owns,
# regardless of state. Filtered out of the Packages system-programs picker so
# the Printing category stays cups's sole menu home (ADR 0079). A function, not
# a hard-coded string at each call site, so a future toggle-owned program is
# added in one place.
printing_owned_programs() { printf '%s\n' cups; }
