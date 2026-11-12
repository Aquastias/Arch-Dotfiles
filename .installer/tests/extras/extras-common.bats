#!/usr/bin/env bats
# Tests for .installer/lib/chroot/extras-common.sh — the DE adapters' line
# edits of config files.

setup() {
  TEST_DIR="$(mktemp -d)"
  CONF="$TEST_DIR/pacman.conf"
  # shellcheck source=../../lib/chroot/extras-common.sh
  source "$BATS_TEST_DIRNAME/../../lib/chroot/extras-common.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "append_after_matching: adds the line right after each match" {
  printf '%s\n' '[options]' 'Color' '[core]' > "$CONF"
  append_after_matching "$CONF" '^\[options\]' 'NoExtract = x'
  run cat "$CONF"
  [ "${lines[0]}" = '[options]' ]
  [ "${lines[1]}" = 'NoExtract = x' ]
  [ "${lines[2]}" = 'Color' ]
}

@test "remove_block: drops each marked block, markers included" {
  printf '%s\n' 'A=1' '# >>> gpu' 'X=1' '# <<< gpu' 'B=2' > "$CONF"
  remove_block "$CONF" '# >>> gpu' '# <<< gpu'
  [ "$(cat "$CONF")" = "$(printf 'A=1\nB=2')" ]
}

@test "remove_block: an unclosed block runs to the end of the file" {
  printf '%s\n' 'A=1' '# >>> gpu' 'X=1' > "$CONF"
  remove_block "$CONF" '# >>> gpu' '# <<< gpu'
  [ "$(cat "$CONF")" = 'A=1' ]
}
