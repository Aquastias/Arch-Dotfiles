#!/usr/bin/env bats
# Tests for lib/common.sh join_list — stdin's lines as one ", "-joined list
# (the human form; `paste -sd', '` cycles its two characters instead).

setup() {
  # shellcheck source=../lib/common.sh
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
}

@test "join_list: three or more lines get a comma and a space each" {
  run join_list < <(printf 'firewalld\nclamav\nrkhunter\nborg\n')
  [ "$output" = "firewalld, clamav, rkhunter, borg" ]
}

@test "join_list: one line stays as it is; blank lines are skipped" {
  run join_list < <(printf '\nalice\n\n')
  [ "$output" = "alice" ]
}

@test "join_list: empty input gives an empty line" {
  run join_list < /dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
