#!/usr/bin/env bats
# Tests for _validation_impermanence() in lib/validation.sh.
# Strategy: stub common.sh helpers; assert that the persist dataset lives on
# the same pool as RPOOL when impermanence is enabled.

setup() {
  TEST_DIR="$(mktemp -d)"
  export CONFIG_FILE="$TEST_DIR/install.jsonc"
  jsonc_strip() { cat "$1"; }
  cfgo()    { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  cfg()     { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  error()   { echo "ERROR: $*" >&2; exit 1; }
  info()    { :; }
  section() { :; }
  warn()    { :; }
  export -f jsonc_strip cfgo cfg error info section warn

  export RPOOL=rpool

  # shellcheck source=../lib/validation.sh
  source "$BATS_TEST_DIRNAME/../lib/validation.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

write_config() { printf '%s\n' "$1" > "$CONFIG_FILE"; }

# ── disabled / missing: pass ─────────────────────────────────────────────────

@test "missing options.impermanence: no error" {
  write_config '{"options": {}}'
  run _validation_impermanence
  [ "$status" -eq 0 ]
}

@test "enabled=false: no error" {
  write_config '{"options":{"impermanence":{"enabled":false}}}'
  run _validation_impermanence
  [ "$status" -eq 0 ]
}

# ── enabled: same-pool check ─────────────────────────────────────────────────

@test "enabled, dataset on rpool: passes" {
  write_config '{"options":{"impermanence":{"enabled":true,
    "dataset":"rpool/persist","mount":"/persist"}}}'
  run _validation_impermanence
  [ "$status" -eq 0 ]
}

@test "enabled, dataset on different pool: errors" {
  write_config '{"options":{"impermanence":{"enabled":true,
    "dataset":"dpool/persist","mount":"/persist"}}}'
  run _validation_impermanence
  [ "$status" -ne 0 ]
  [[ "$output" =~ "same pool" ]]
}

@test "enabled, dataset has no slash: errors" {
  write_config '{"options":{"impermanence":{"enabled":true,
    "dataset":"justpool","mount":"/persist"}}}'
  run _validation_impermanence
  [ "$status" -ne 0 ]
}
