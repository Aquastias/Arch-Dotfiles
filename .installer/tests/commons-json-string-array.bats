#!/usr/bin/env bats
# Tests for lib/common.sh json_string_array — the Installer Stdlib's way to
# turn words into a JSON array (jq's -R/-s are outside ADR 0167's flags).

setup() {
  # shellcheck source=../lib/common.sh
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
}

@test "json_string_array: each argument becomes one string, in order" {
  run json_string_array zsh 'with space' 'quote"d'
  [ "$status" -eq 0 ]
  [ "$output" = '["zsh","with space","quote\"d"]' ]
}

@test "json_string_array: no arguments give an empty array" {
  run json_string_array
  [ "$output" = '[]' ]
}

@test "json_string_array: an empty argument stays an empty string" {
  run json_string_array a ''
  [ "$output" = '["a",""]' ]
}
