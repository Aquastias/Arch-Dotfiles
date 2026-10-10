#!/usr/bin/env bats
# Tests for lib/common.sh join_words — the Installer Stdlib's whitespace
# squeezer (stands in for `… | xargs` as a trim; ADR 0153 Tool Tiers).

setup() {
  # shellcheck source=../lib/common.sh
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
}

@test "join_words: trims and squeezes one line" {
  run join_words <<<"   40G   Samsung SSD  "
  [ "$output" = "40G Samsung SSD" ]
}

@test "join_words: joins several lines with single spaces" {
  run join_words < <(printf 'rpool\n  dpool\n\ntank\n')
  [ "$output" = "rpool dpool tank" ]
}

@test "join_words: empty input gives an empty line" {
  run join_words < /dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
