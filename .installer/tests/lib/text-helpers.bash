#!/usr/bin/env bash
# tests/lib/text-helpers.bash — text assertions shared by the bats suites
# (ADR 0167). Used by: bats files that `load` it (lib/text-helpers from
# tests/, ../lib/text-helpers from a subdirectory).
#
#   line_number_of <file> <words> — the number of the first line of <file>
#                                   that contains <words> ("" when none)

line_number_of() {
  local -a file_lines
  local i
  mapfile -t file_lines < "$1"
  for i in "${!file_lines[@]}"; do
    if [[ "${file_lines[i]}" == *"$2"* ]]; then
      printf '%s\n' "$((i + 1))"
      return 0
    fi
  done
}
