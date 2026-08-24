#!/usr/bin/env bash
# =============================================================================
# lib/config/mirrors.sh — Mirror Service resolver (ADR 0089)
# =============================================================================
# Pure core turning the Mirrors & Repositories menu section into its owned Host
# Program: `reflector`. Unlike the Printing/Bluetooth/Power toggles this is
# state-independent — the section always brings reflector (the mirror-ranking
# tool it configures), so a weekly reflector.timer keeps the installed mirror
# list fresh. `reflector` is NOT declared in Host Core; its sole home is the
# Mirrors & Repositories section (like cups' home is Printing, ADR 0079).
#
# The single source of truth shared by the Effective-Config injector
# (emit.sh / profile.sh assembly) and the Package Resolver, so the two can
# never drift. No TTY, no disk writes — JSON in, decision out.
#
# Public API:
#   mirrors_programs        <config-json> → derived Host Programs, one/line
#   mirrors_inject          <config-json> → config with the derived programs
#                                           folded into .host_programs
#   mirrors_owned_programs                → every program the section owns
#                                           (picker filter)
# =============================================================================

# mirrors_programs <config-json> — the section-derived Host Programs, one per
# line: always `reflector`. State-independent (the config arg is accepted for
# signature parity with the toggle resolvers, not read). The source of truth
# both the injector and the resolver consume.
mirrors_programs() {
  printf '%s\n' reflector
}

# mirrors_inject <config-json> — the config with the section-derived Host
# Programs (mirrors_programs) folded into .host_programs (order-preserving,
# idempotent), so the Runner installs reflector exactly as an authored Host
# Program. Pure: JSON in, compact JSON out.
mirrors_inject() {
  local cfg="${1:-{\}}" progs
  progs="$(mirrors_programs "$cfg")"
  [[ -n "$progs" ]] || { jq -c . <<<"$cfg"; return; }
  jq -c --arg progs "$progs" '
    ($progs | split("\n") | map(select(length > 0))) as $add
    | .host_programs = ((.host_programs // []) as $sp
        | reduce $add[] as $p ($sp;
            if (. | index($p)) then . else . + [$p] end))
  ' <<<"$cfg"
}

# mirrors_owned_programs — every Host Program the Mirrors & Repositories section
# owns. Filtered out of the Packages host-programs picker so the section stays
# reflector's sole menu home (ADR 0089). A function, not a hard-coded string at
# each call site.
mirrors_owned_programs() { printf '%s\n' reflector; }
