#!/usr/bin/env bats
# Tests for .os/lib/config/state.sh — the Guided Installer's Config State
# (ADR 0039): a sparse override map over the computed defaults, mutated by
# pure verbs (get/set/unset/emit), JSON-in/JSON-out, no TTY.
#
# Behaviour under test (external only — the state a verb produces and the
# override map it emits), never internal structure.

setup() {
  error() { echo "[error] $*" >&2; return 1; }
  export -f error

  # shellcheck source=../../lib/config/state.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
}

# ── tracer: set a field, see it in the emitted override map ─────────────────

@test "cfgstate_set: a set field appears in the emitted override map" {
  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"

  run cfgstate_emit "$state"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.hostname == "eterniox"'
}

# ── get: read back a set override (raw value) ──────────────────────────────

@test "cfgstate_get: returns the raw value at a set path" {
  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"

  run cfgstate_get "$state" system.hostname
  [ "$status" -eq 0 ]
  [ "$output" = "eterniox" ]
}

@test "cfgstate_get: an unset path yields empty" {
  run cfgstate_get "$(cfgstate_new)" system.hostname
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── unset: drop one override, leave the rest ───────────────────────────────

@test "cfgstate_unset: clears one override and keeps the others" {
  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  state="$(cfgstate_set "$state" mode '"single"')"
  state="$(cfgstate_unset "$state" system.hostname)"

  run cfgstate_emit "$state"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("system") | not'
  echo "$output" | jq -e '.mode == "single"'
}

# ── is_overridden: the ● predicate the menu model reads ────────────────────

@test "cfgstate_is_overridden: true for a set path, false for an unset one" {
  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"

  run cfgstate_is_overridden "$state" system.hostname
  [ "$status" -eq 0 ]

  run cfgstate_is_overridden "$state" mode
  [ "$status" -ne 0 ]
}

# ── reset granularities (issue 02): field / section / all, all via the sparse
#    map. Field = unset a leaf, section = unset a path prefix (drops the whole
#    subtree), all = a fresh state. Each leaves no trace of what it cleared.

@test "reset(field): unset a leaf clears just that field, siblings remain" {
  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  state="$(cfgstate_set "$state" system.locale '"de_DE.UTF-8"')"

  run cfgstate_unset "$state" system.hostname
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system | has("hostname") | not'
  echo "$output" | jq -e '.system.locale == "de_DE.UTF-8"'
}

@test "reset(section): unset a prefix drops the whole subtree, others remain" {
  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  state="$(cfgstate_set "$state" system.locale '"de_DE.UTF-8"')"
  state="$(cfgstate_set "$state" filesystem '"zfs"')"

  run cfgstate_unset "$state" system
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("system") | not'      # whole section gone
  echo "$output" | jq -e '.filesystem == "zfs"'      # sibling section intact
}

@test "reset(all): a fresh state carries none of the overrides" {
  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"eterniox"')"
  state="$(cfgstate_set "$state" filesystem '"zfs"')"

  run cfgstate_emit "$(cfgstate_new)"        # reset-all == a fresh state
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. == {}'
}
