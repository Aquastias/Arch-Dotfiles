#!/usr/bin/env bats
# Tests for .os/lib/layout-multi.sh — pure topology suggestion functions.
# suggest_os_topologies and suggest_storage_topologies have no system calls.

setup() {
  TEST_DIR="$(mktemp -d)"
  CONFIG_FILE="$TEST_DIR/install.json"
  export CONFIG_FILE
  printf '{}' > "$CONFIG_FILE"
  # shellcheck source=../lib/common.sh
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
  # shellcheck source=../lib/zfs-pools.sh
  source "$BATS_TEST_DIRNAME/../lib/zfs-pools.sh"
  # shellcheck source=../lib/layout-multi.sh
  source "$BATS_TEST_DIRNAME/../lib/layout-multi.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── suggest_os_topologies ─────────────────────────────────────────────────────

@test "suggest_os_topologies(1): emits exactly one line" {
  run suggest_os_topologies 1
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l)" -eq 1 ]
}

@test "suggest_os_topologies(1): the single option is none" {
  run suggest_os_topologies 1
  [ "$status" -eq 0 ]
  [[ "$output" == none* ]]
}

@test "suggest_os_topologies(2): first recommendation is mirror" {
  run suggest_os_topologies 2
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | head -1)" == mirror* ]]
}

@test "suggest_os_topologies(3): includes mirror as an option" {
  run suggest_os_topologies 3
  [ "$status" -eq 0 ]
  [[ "$output" == *mirror* ]]
}

# ── suggest_storage_topologies ────────────────────────────────────────────────

@test "suggest_storage_topologies(1): first recommendation is independent" {
  run suggest_storage_topologies 1
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | head -1)" == independent* ]]
}

@test "suggest_storage_topologies(2): first recommendation is mirror" {
  run suggest_storage_topologies 2
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | head -1)" == mirror* ]]
}

@test "suggest_storage_topologies(3): first recommendation is raidz1" {
  run suggest_storage_topologies 3
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | head -1)" == raidz1* ]]
}

@test "suggest_storage_topologies(4): first recommendation is raidz1" {
  run suggest_storage_topologies 4
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | head -1)" == raidz1* ]]
}

@test "suggest_storage_topologies(5): first recommendation is raidz2" {
  run suggest_storage_topologies 5
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | head -1)" == raidz2* ]]
}

@test "suggest_storage_topologies(6): first recommendation is raidz2" {
  run suggest_storage_topologies 6
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | head -1)" == raidz2* ]]
}
