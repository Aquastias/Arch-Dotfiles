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
# Host Program. `options.ssh.enabled` only enables a service on the
# always-present `openssh`, whereas this toggle gates the install itself, so
# cups is genuinely absent when off. The toggle defaults ON to preserve the
# historical "cups installed on every host" behaviour.
#
# The toggle predicate lives in exactly one place (printing_enabled);
# printing_programs derives the program list from it, and printing_inject folds
# whatever printing_programs emits into host_programs — so the `cups` literal
# and the on/off rule are never re-encoded per consumer.
#
# Public API:
#   printing_enabled          <config-json> → "true" | "false" (default on)
#   printing_programs         <config-json> → derived Host Programs, one/line
#   printing_inject           <config-json> → config with the derived programs
#                                             folded into .host_programs
#   printing_owned_programs                 → every program the toggle owns,
#                                             state-independent (picker filter)
# =============================================================================

# printing_enabled <config-json> — "true" unless the toggle is explicitly
# false (absent ⇒ on, matching the default-on accessor). The sole on/off rule;
# every other function derives from it. An explicit null check so a stored
# `false` round-trips rather than being read as absent.
printing_enabled() {
  jq -r '(.options.printing.enabled) as $v
    | if $v == false then "false" else "true" end' <<<"${1:-{\}}"
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
  local cfg="${1:-{\}}" progs
  progs="$(printing_programs "$cfg")"
  # Nothing derived (printing off) → the config is untouched, not given an empty
  # host_programs it never had.
  [[ -n "$progs" ]] || { jq -c . <<<"$cfg"; return; }
  jq -c --arg progs "$progs" '
    ($progs | split("\n") | map(select(length > 0))) as $add
    | .host_programs = ((.host_programs // []) as $sp
        | reduce $add[] as $p ($sp;
            if (. | index($p)) then . else . + [$p] end))
  ' <<<"$cfg"
}

# printing_owned_programs — every Host Program the Printing toggle owns,
# regardless of state. Filtered out of the Packages system-programs picker so
# the Printing category stays cups's sole menu home (ADR 0079). A function, not
# a hard-coded string at each call site, so a future toggle-owned program is
# added in one place.
printing_owned_programs() { printf '%s\n' cups; }
