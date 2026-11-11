#!/usr/bin/env bash
# tests/lib/json-helpers.bash — JSON assertions shared by the bats suites
# (ADR 0167: each jq test reads as one named step).
# Used by: bats files that `load` it (lib/json-helpers from tests/,
# ../lib/json-helpers from a subdirectory).
#
#   output_satisfies <jq-test>      — the JSON in $output makes <jq-test> true
#   json_satisfies <json> <jq-test> — the given JSON makes <jq-test> true
#
# Both fail (non-zero) when the test is false or null, or the JSON does not
# parse, so a bats test stops right there.

output_satisfies() {
  json_satisfies "$output" "$1"
}

json_satisfies() {
  # Whether the JSON makes the test true.
  printf '%s\n' "$1" | jq -e "$2" >/dev/null
}
