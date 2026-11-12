#!/usr/bin/env bats
# Tests for lib/common.sh text_before / text_after / text_after_last — split a
# text on a separator (they stand in for ${x%%sep*}, ${x#*sep}, ${x##*sep};
# ADR 0167).

setup() {
  # shellcheck source=../lib/common.sh
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
}

@test "text_before: the text before the first separator" {
  run text_before 'Mirrors & Repositories — 3 mirrors — on' ' — '
  [ "$output" = "Mirrors & Repositories" ]
}

@test "text_before: no separator gives the whole text" {
  run text_before 'Users' ' — '
  [ "$output" = "Users" ]
}

@test "text_after: the text after the first separator" {
  run text_after 'notice a — b' ' '
  [ "$output" = "a — b" ]
}

@test "text_after: no separator gives the whole text" {
  run text_after 'render' ' '
  [ "$output" = "render" ]
}

@test "text_after_last: the text after the last separator" {
  run text_after_last '/usr/bin/zsh' '/'
  [ "$output" = "zsh" ]
}

@test "text_after_last: no separator gives the whole text" {
  run text_after_last 'zsh' '/'
  [ "$output" = "zsh" ]
}

@test "text_before: a separator at the start gives an empty text" {
  run text_before ' — x' ' — '
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "an empty text gives an empty text, never null" {
  [ "$(text_before '' ' — ')" = "" ]
  [ "$(text_after '' ' ')" = "" ]
  [ "$(text_after_last '' '/')" = "" ]
}
