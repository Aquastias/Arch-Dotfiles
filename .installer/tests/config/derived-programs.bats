#!/usr/bin/env bats
# Tests for lib/config/derived-programs.sh — folding the toggle-derived Host
# Programs (printing, bluetooth, power, mirrors) into host_programs.

load ../lib/json-helpers

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/config/derived-programs.sh"
}

@test "derived_programs_inject: appends what is missing, in order, once" {
  run derived_programs_inject '{"host_programs":["zsh","cups"]}' \
    "$(printf '%s\n' cups bluetooth)"
  [ "$status" -eq 0 ]
  [ "$output" = '{"host_programs":["zsh","cups","bluetooth"]}' ]
}

@test "derived_programs_inject: creates host_programs when absent" {
  run derived_programs_inject '{"a":1}' reflector
  [ "$output" = '{"a":1,"host_programs":["reflector"]}' ]
}

@test "derived_programs_inject: nothing derived leaves the config as it is" {
  run derived_programs_inject '{"a":1}' ''
  [ "$output" = '{"a":1}' ]
}
