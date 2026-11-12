#!/usr/bin/env bats
# Tests for .installer/lib/shell/files.sh — line edits of config files.

setup() {
  TEST_DIR="$(mktemp -d)"
  CONF="$TEST_DIR/app.conf"
  # The helpers run their file access as root; here, as the test user.
  sudo() { "$@"; }
  # shellcheck source=../../lib/shell/files.sh
  source "$BATS_TEST_DIRNAME/../../lib/shell/files.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "remove_lines_matching: drops matching lines, keeps the rest" {
  printf '%s\n' '#user = "x"' 'user = "y"' 'group = "z"' > "$CONF"
  remove_lines_matching "$CONF" '^#?user *='
  [ "$(cat "$CONF")" = 'group = "z"' ]
}

@test "remove_lines_matching: every line matching leaves an empty file" {
  printf '%s\n' 'user = 1' 'user = 2' > "$CONF"
  remove_lines_matching "$CONF" '^user'
  [ ! -s "$CONF" ]
}

@test "remove_lines_matching: keeps the file's mode" {
  printf 'a\nb\n' > "$CONF"
  chmod 640 "$CONF"
  remove_lines_matching "$CONF" '^a'
  [ "$(stat -c %a "$CONF")" = 640 ]
}

@test "insert_before_matching: puts the text right before each match" {
  printf '%s\n' '# head' '*filter' 'rule' > "$CONF"
  insert_before_matching "$CONF" '^\*filter' $'*nat\nCOMMIT\n'
  run cat "$CONF"
  [ "${lines[0]}" = '# head' ]
  [ "${lines[1]}" = '*nat' ]
  [ "${lines[2]}" = 'COMMIT' ]
  [ "${lines[3]}" = '*filter' ]
}
