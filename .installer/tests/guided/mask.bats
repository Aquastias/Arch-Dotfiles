#!/usr/bin/env bats
# Tests for .installer/lib/guided/mask.sh — the inline password masking core (ADR 0051).
# Two strings in (previous buffer, new fzf query), two lines out (reconstructed
# buffer, bullet display). The append + backspace-at-end contract the live front-
# end guarantees by unbinding cursor movement on the password screen.

setup() { source "$BATS_TEST_DIRNAME/../../lib/guided/mask.sh"; }

B='•'   # the bullet

buffer() { guided_mask_apply "$1" "$2" | awk 'NR == 1'; }
display() { guided_mask_apply "$1" "$2" | awk 'END { print }'; }

@test "append one char to an empty buffer" {
  [ "$(buffer '' 's')" = "s" ]
  [ "$(display '' 's')" = "$B" ]
}

@test "append a char onto masked bullets keeps the real buffer" {
  # previous buffer 'ab', query is 2 bullets + the newly typed 'c'
  [ "$(buffer 'ab' "${B}${B}c")" = "abc" ]
  [ "$(display 'ab' "${B}${B}c")" = "${B}${B}${B}" ]
}

@test "paste of several chars appends them all" {
  [ "$(buffer 'ab' "${B}${B}xyz")" = "abxyz" ]
  [ "$(display 'ab' "${B}${B}xyz")" = "${B}${B}${B}${B}${B}" ]
}

@test "backspace-at-end truncates the buffer" {
  # buffer 'abc', query dropped one bullet → 2 bullets
  [ "$(buffer 'abc' "${B}${B}")" = "ab" ]
  [ "$(display 'abc' "${B}${B}")" = "${B}${B}" ]
}

@test "backspace to empty clears the buffer" {
  [ "$(buffer 'a' '')" = "" ]
  [ "$(display 'a' '')" = "" ]
}

@test "unchanged query (same length) leaves the buffer intact" {
  [ "$(buffer 'abc' "${B}${B}${B}")" = "abc" ]
}

@test "typing a full secret one char at a time reconstructs it" {
  local buffer='' query character disp
  for character in s 3 c r e t; do
    query="${disp:-}${character}"
    buffer="$(guided_mask_apply "$buffer" "$query" | awk 'NR == 1')"
    disp="$(guided_mask_apply "$buffer" "$query" | awk 'END { print }')"
  done
  [ "$buffer" = "s3cret" ]
  [ "${#disp}" -eq 6 ]
}
