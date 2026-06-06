#!/usr/bin/env bats
# Tests for _validation_impermanence() in lib/config/validation.sh.
# Strategy: stub common.sh helpers; assert that the persist dataset lives on
# the same pool as RPOOL when impermanence is enabled.

setup() {
  TEST_DIR="$(mktemp -d)"
  export CONFIG_FILE="$TEST_DIR/install.jsonc"
  jsonc_strip() { cat "$1"; }
  jsonc_read() { jsonc_strip "$1" | jq -r "$2"; }
  cfgo()    { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  cfg()     { jsonc_strip "$CONFIG_FILE" | jq -r "${1} // empty"; }
  error()   { echo "ERROR: $*" >&2; exit 1; }
  info()    { :; }
  section() { :; }
  warn()    { :; }
  export -f jsonc_strip jsonc_read cfgo cfg error info section warn

  export RPOOL=rpool

  # shellcheck source=../../lib/config/accessors.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/accessors.sh"
  # shellcheck source=../../lib/config/validation.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/validation.sh"
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

# ── persist paths: errors ───────────────────────────────────────────────────

@test "persist dir path must be absolute" {
  local json='{"persist":{"directories":["relative/path"],"files":[]}}'
  run _validation_persist "$json"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "must be absolute" ]]
  [[ "$output" =~ "relative/path" ]]
}

@test "persist file path must be absolute" {
  local json='{"persist":{"directories":[],"files":["foo.conf"]}}'
  run _validation_persist "$json"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "must be absolute" ]]
}

@test "persist path must not contain ..  " {
  local json='{"persist":{"directories":["/etc/../bad"],"files":[]}}'
  run _validation_persist "$json"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "must not contain" ]]
}

@test "persist path must not contain ~" {
  local json='{"persist":{"directories":["/~/bad"],"files":[]}}'
  run _validation_persist "$json"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "must not contain" ]]
}

@test "persist file that exists as directory: errors" {
  mkdir -p "$TEST_DIR/etc/wireguard"
  local json
  json='{"persist":{"directories":[],"files":["'"$TEST_DIR"'/etc/wireguard"]}}'
  run _validation_persist "$json"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "is a directory on disk" ]]
  [[ "$output" =~ "Move to persist.directories" ]]
}

@test "persist directory that exists as file: errors" {
  mkdir -p "$TEST_DIR/etc"
  printf x > "$TEST_DIR/etc/foo.conf"
  local json
  json='{"persist":{"directories":["'"$TEST_DIR"'/etc/foo.conf"],"files":[]}}'
  run _validation_persist "$json"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "is a file on disk" ]]
  [[ "$output" =~ "Move to persist.files" ]]
}

@test "persist: clean dirs and files pass" {
  mkdir -p "$TEST_DIR/etc/wireguard" "$TEST_DIR/etc"
  printf x > "$TEST_DIR/etc/foo.conf"
  local json
  json='{"persist":{"directories":["'"$TEST_DIR"'/etc/wireguard"],'
  json+='"files":["'"$TEST_DIR"'/etc/foo.conf"]}}'
  run _validation_persist "$json"
  [ "$status" -eq 0 ]
}

# ── persist paths: warnings ─────────────────────────────────────────────────

@test "persist: warn when path under /home (already persistent)" {
  local log="$TEST_DIR/warn.log"
  warn() { printf '%s\n' "$*" >> "$log"; }
  export -f warn
  local json='{"persist":{"directories":["/home/foo"],"files":[]}}'
  run _validation_persist "$json"
  [ "$status" -eq 0 ]
  [ -f "$log" ]
  grep -qE "already persistent" "$log"
  grep -qE "/home/foo" "$log"
}

@test "persist: warn when path under /var, /var/log, /var/cache, /tmp" {
  local log="$TEST_DIR/warn.log"
  warn() { printf '%s\n' "$*" >> "$log"; }
  export -f warn
  for prefix in /var /var/log /var/cache /tmp; do
    local json
    json='{"persist":{"directories":["'"$prefix"'/x"],"files":[]}}'
    run _validation_persist "$json"
    [ "$status" -eq 0 ]
  done
  for prefix in /var /var/log /var/cache /tmp; do
    grep -qE "$prefix" "$log" || { echo "missing $prefix"; return 1; }
  done
}

@test "persist: warn when path is in curated defaults" {
  local log="$TEST_DIR/warn.log"
  warn() { printf '%s\n' "$*" >> "$log"; }
  export -f warn
  local json='{"persist":{"directories":["/etc/ssh"],"files":[]}}'
  run _validation_persist "$json"
  [ "$status" -eq 0 ]
  grep -qE "curated defaults" "$log"
}

@test "persist: warn when path is curated file (CURATED_FILES)" {
  local log="$TEST_DIR/warn.log"
  warn() { printf '%s\n' "$*" >> "$log"; }
  export -f warn
  local json='{"persist":{"directories":[],"files":["/etc/machine-id"]}}'
  run _validation_persist "$json"
  [ "$status" -eq 0 ]
  grep -qE "curated defaults" "$log"
  grep -qE "/etc/machine-id" "$log"
}

@test "persist: warn when declared while impermanence disabled" {
  local log="$TEST_DIR/warn.log"
  warn() { printf '%s\n' "$*" >> "$log"; }
  export -f warn
  write_config '{"options":{"impermanence":{"enabled":false}}}'
  local json='{"persist":{"directories":["/etc/wireguard"],"files":[]}}'
  run _validation_persist "$json"
  [ "$status" -eq 0 ]
  grep -qE "impermanence is disabled" "$log"
}

@test "persist: NO disabled-warning when impermanence enabled" {
  local log="$TEST_DIR/warn.log"
  warn() { printf '%s\n' "$*" >> "$log"; }
  export -f warn
  write_config '{"options":{"impermanence":{"enabled":true,
    "dataset":"rpool/persist"}}}'
  local json='{"persist":{"directories":["/etc/wireguard"],"files":[]}}'
  run _validation_persist "$json"
  [ "$status" -eq 0 ]
  if [[ -f "$log" ]] && grep -qE "impermanence is disabled" "$log"; then
    return 1
  fi
}
