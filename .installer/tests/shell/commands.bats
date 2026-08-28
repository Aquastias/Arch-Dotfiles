#!/usr/bin/env bats
# Tests for .os/lib/shell/commands.sh — command_exists helper.

setup() {
  # shellcheck source=../../lib/shell/commands.sh
  source "$BATS_TEST_DIRNAME/../../lib/shell/commands.sh"
}

@test "command_exists: returns 0 for a known-present command (bash)" {
  run command_exists bash
  [ "$status" -eq 0 ]
}

@test "command_exists: returns non-zero for an absent command" {
  run command_exists __definitely_not_a_real_command_xyz123__
  [ "$status" -ne 0 ]
}
