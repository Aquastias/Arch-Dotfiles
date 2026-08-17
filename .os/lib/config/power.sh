#!/usr/bin/env bash
# =============================================================================
# lib/config/power.sh — Power Profile resolver (ADR 0080)
# =============================================================================
# Pure core turning a host's `options.power.profile` choice into a toggle-
# derived Host Program. The ENUM generalisation of the printing/bluetooth
# pattern (ADR 0079/0080): unlike a bool toggle — which only decides WHETHER a
# package lands — the value picks WHICH daemon is installed and whose service is
# enabled. `power-profiles-daemon` (the default) and `tuned` each map to a
# Host Program of the same name; `none` derives nothing.
#
# DE-agnostic: the daemon works with or without KDE (powerprofilesctl / tuned-
# adm drive it headlessly). power-profiles-daemon is only an optional dep of
# Powerdevil, so this key genuinely adds it even on KDE. The tuned program pulls
# tuned-ppd so a KDE/Hyprland applet keeps a working switcher.
#
# The value predicate lives in exactly one place (power_profile); power_programs
# derives the program list, and power_inject folds it into host_programs — so
# the value→program mapping is never re-encoded per consumer. JSON in, decision
# out. No TTY, no disk writes.
#
# Public API:
#   power_profile           <config-json> → none | power-profiles-daemon | tuned
#                                            (absent ⇒ power-profiles-daemon)
#   power_programs          <config-json> → derived Host Program, one/line
#   power_inject            <config-json> → config with the derived program
#                                            folded into .host_programs
#   power_owned_programs                  → every program the enum can own,
#                                            state-independent (picker filter)
# =============================================================================

# power_profile <config-json> — the selected backend. Absent/null/empty ⇒
# power-profiles-daemon (the default); an explicit value (incl. `none`) wins.
power_profile() {
  jq -r '(.options.power.profile) as $v
    | if ($v == null or $v == "") then "power-profiles-daemon" else $v end' \
    <<<"${1:-{\}}"
}

# power_programs <config-json> — the toggle-derived Host Program for the
# selected backend, one per line: the value IS the program name for ppd/tuned;
# `none` (or any unrecognised value) yields nothing. The source of truth both
# the injector and the resolver consume, so neither re-encodes the mapping.
power_programs() {
  case "$(power_profile "${1:-{\}}")" in
  power-profiles-daemon | tuned) printf '%s\n' "$(power_profile "${1:-{\}}")" ;;
  esac
  return 0
}

# power_inject <config-json> — the config with the derived Host Program folded
# into .host_programs (order-preserving, idempotent). A no-op when power
# yields nothing (`none`). Pure: JSON in, compact JSON out.
power_inject() {
  local cfg="${1:-{\}}" progs
  progs="$(power_programs "$cfg")"
  [[ -n "$progs" ]] || { jq -c . <<<"$cfg"; return; }
  jq -c --arg progs "$progs" '
    ($progs | split("\n") | map(select(length > 0))) as $add
    | .host_programs = ((.host_programs // []) as $sp
        | reduce $add[] as $p ($sp;
            if (. | index($p)) then . else . + [$p] end))
  ' <<<"$cfg"
}

# power_owned_programs — every Host Program the Power enum can own, regardless
# of the selected value. Filtered out of the Packages system-programs picker so
# the Power category stays their sole menu home (ADR 0080). A function, not
# hard-coded strings at each call site.
power_owned_programs() { printf '%s\n' power-profiles-daemon tuned; }
