#!/usr/bin/env bash
# =============================================================================
# lib/config/state.sh — Guided Installer Config State (ADR 0039)
# =============================================================================
# A single in-session Config State: a *sparse override map* over the computed
# defaults (Host Core + accessors). The Guided Installer mutates it through the
# pure verbs below and emits only what the operator changed; the back-end fills
# the rest. Pure: in-memory JSON on stdin/args → JSON on stdout, no TTY.
#
# Public API:
#   cfgstate_new                       → fresh (empty) state on stdout
#   cfgstate_set   <state> <path> <v>  → state with override at <path> = <v>
#   cfgstate_get   <state> <path>      → raw value at <path> (empty if unset)
#   cfgstate_unset <state> <path>      → state with the override at <path> gone
#   cfgstate_is_overridden <state> <p> → rc 0 if <p> is overridden, else 1
#   cfgstate_emit  <state>             → the sparse override map (delta)
#
# <path> is a dotted JSON path ("system.hostname"); <v> is a JSON value
# ('"eterniox"', 'true', '"single"').
# =============================================================================

# cfgstate_new — the initial state: an empty override map.
cfgstate_new() { printf '%s\n' '{}'; }

# cfgstate_set <state> <path> <json-value> — record an override at <path>.
cfgstate_set() {
  local state="$1" path="$2" value="$3"
  jq --arg p "$path" --argjson v "$value" \
    'setpath($p | split("."); $v)' <<<"$state"
}

# cfgstate_get <state> <path> — the raw value at <path>, empty when unset.
cfgstate_get() {
  local state="$1" path="$2"
  jq -r --arg p "$path" 'getpath($p | split(".")) // empty' <<<"$state"
}

# cfgstate_unset <state> <path> — drop the override at <path>. Ancestor
# objects emptied by the deletion are pruned, so a reset field leaves no trace
# in the sparse map (the section disappears when its last override is gone).
cfgstate_unset() {
  local state="$1" path="$2"
  jq --arg p "$path" '
    delpaths([$p | split(".")])
    | walk(if type == "object" then with_entries(select(.value != {})) else . end)
  ' <<<"$state"
}

# cfgstate_is_overridden <state> <path> — rc 0 when <path> carries an
# override, rc 1 otherwise. Drives the menu's ● flag.
cfgstate_is_overridden() {
  local state="$1" path="$2"
  jq -e --arg p "$path" 'getpath($p | split(".")) != null' <<<"$state" >/dev/null
}

# cfgstate_emit <state> — the sparse override map (a profile delta).
cfgstate_emit() { jq '.' <<<"$1"; }
