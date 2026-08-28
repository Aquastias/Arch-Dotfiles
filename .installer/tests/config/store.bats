#!/usr/bin/env bats
# Tests for .os/lib/config/store.sh — the Config Store, the effectful edge over
# the pure Config State. Owns the triad session files behind named verbs so no
# caller pokes the tmpfs paths directly. Pure round-trip through the file: set a
# GUIDED_*_FILE, read it back.

setup() {
  TEST_DIR="$(mktemp -d)"
  export GUIDED_STATE_FILE="$TEST_DIR/state.json"
  export GUIDED_NAV_FILE="$TEST_DIR/nav.json"
  export GUIDED_BASELINE_FILE="$TEST_DIR/base.json"
  source "$BATS_TEST_DIRNAME/../../lib/config/store.sh"
}
teardown() { rm -rf "$TEST_DIR"; }

@test "state: write then read round-trips" {
  cfgstore_write_state '{"system":{"hostname":"box"}}'
  [ "$(cfgstore_state)" = '{"system":{"hostname":"box"}}' ]
}

@test "nav: write then read round-trips" {
  cfgstore_write_nav '{"screen":"category","category":"System"}'
  [ "$(cfgstore_nav)" = '{"screen":"category","category":"System"}' ]
}

@test "baseline: write then read round-trips" {
  cfgstore_write_baseline '{"users":["aquastias"]}'
  [ "$(cfgstore_baseline)" = '{"users":["aquastias"]}' ]
}

@test "baseline: falls back to empty map when the file is absent" {
  rm -f "$GUIDED_BASELINE_FILE"
  [ "$(cfgstore_baseline)" = '{}' ]
}

@test "baseline: falls back to empty map when the path is unset" {
  unset GUIDED_BASELINE_FILE
  [ "$(cfgstore_baseline)" = '{}' ]
}
