#!/usr/bin/env bats
# Tests for .installer/lib/config/config-state.sh — the Guided Installer's Config State
# (ADR 0039): a sparse override map over the computed defaults, mutated by
# pure verbs (get/set/unset/emit), JSON-in/JSON-out, no TTY.
#
# Behaviour under test (external only — the state a verb produces and the
# override map it emits), never internal structure.

setup() {
  error() { echo "[error] $*" >&2; return 1; }
  export -f error

  # shellcheck source=../../lib/config/config-state.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/config-state.sh"
}

# ── tracer: set a field, see it in the emitted override map ─────────────────

@test "config_state_set: a set field appears in the emitted override map" {
  state="$(config_state_set "$(config_state_new)" system.hostname '"eterniox"')"

  run config_state_emit "$state"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.hostname == "eterniox"'
}

# ── get: read back a set override (raw value) ──────────────────────────────

@test "config_state_get: returns the raw value at a set path" {
  state="$(config_state_set "$(config_state_new)" system.hostname '"eterniox"')"

  run config_state_get "$state" system.hostname
  [ "$status" -eq 0 ]
  [ "$output" = "eterniox" ]
}

@test "config_state_get: an unset path yields empty" {
  run config_state_get "$(config_state_new)" system.hostname
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── a stored `false` is a value, not "unset" — distinguish it from null ─────
# Regression: `getpath // empty` swallowed `false` (jq's // treats false as
# empty), so a false bool read back as "". A bool field set to false must
# round-trip as "false", or the menu and edits can't tell off from unset.

@test "config_state_get: a stored false round-trips as \"false\", not empty" {
  state="$(config_state_set "$(config_state_new)" options.multilib 'false')"

  run config_state_get "$state" options.multilib
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

# ── unset: drop one override, leave the rest ───────────────────────────────

@test "config_state_unset: clears one override and keeps the others" {
  state="$(config_state_set "$(config_state_new)" system.hostname '"eterniox"')"
  state="$(config_state_set "$state" mode '"single"')"
  state="$(config_state_unset "$state" system.hostname)"

  run config_state_emit "$state"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("system") | not'
  echo "$output" | jq -e '.mode == "single"'
}

# ── is_overridden: the ● predicate the menu model reads ────────────────────

@test "config_state_is_overridden: true for a set path, false for an unset one" {
  state="$(config_state_set "$(config_state_new)" system.hostname '"eterniox"')"

  run config_state_is_overridden "$state" system.hostname
  [ "$status" -eq 0 ]

  run config_state_is_overridden "$state" mode
  [ "$status" -ne 0 ]
}

# ── reset granularities (issue 02): field / section / all, all via the sparse
#    map. Field = unset a leaf, section = unset a path prefix (drops the whole
#    subtree), all = a fresh state. Each leaves no trace of what it cleared.

@test "reset(field): unset a leaf clears just that field, siblings remain" {
  state="$(config_state_set "$(config_state_new)" system.hostname '"eterniox"')"
  state="$(config_state_set "$state" system.locale '"de_DE.UTF-8"')"

  run config_state_unset "$state" system.hostname
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system | has("hostname") | not'
  echo "$output" | jq -e '.system.locale == "de_DE.UTF-8"'
}

@test "reset(section): unset a prefix drops the whole subtree, others remain" {
  state="$(config_state_set "$(config_state_new)" system.hostname '"eterniox"')"
  state="$(config_state_set "$state" system.locale '"de_DE.UTF-8"')"
  state="$(config_state_set "$state" filesystem '"zfs"')"

  run config_state_unset "$state" system
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("system") | not'      # whole section gone
  echo "$output" | jq -e '.filesystem == "zfs"'      # sibling section intact
}

@test "reset(all): a fresh state carries none of the overrides" {
  state="$(config_state_set "$(config_state_new)" system.hostname '"eterniox"')"
  state="$(config_state_set "$state" filesystem '"zfs"')"

  run config_state_emit "$(config_state_new)"        # reset-all == a fresh state
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. == {}'
}
