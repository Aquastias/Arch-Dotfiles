#!/usr/bin/env bash
# tests/lib/text-helpers.bash — text assertions shared by the bats suites
# (ADR 0167). Used by: bats files that `load` it (lib/text-helpers from
# tests/, ../lib/text-helpers from a subdirectory).
#
#   output_has_line <line>        — one line of $output is exactly <line>
#   first_line_matching <file> <re> — first line matching <re>, by number
#   last_line_matching <file> <re>  — last line matching <re>, by number
#   function_body <file> <name>     — one function definition of <file>
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

# output_has_line <line> — 0 when one line of the last `run`'s output is
# exactly <line> (bats keeps the lines in ${lines[@]}).
# shellcheck disable=SC2154  # bats sets lines
output_has_line() {
  local line
  for line in "${lines[@]}"; do
    [[ "$line" == "$1" ]] && return 0
  done
  return 1
}

# first_line_matching <file> <extended-regex> — the number of the first line
# of <file> that matches ("" when none does).
first_line_matching() {
  local -a file_lines
  local i
  mapfile -t file_lines < "$1"
  for i in "${!file_lines[@]}"; do
    if [[ "${file_lines[i]}" =~ $2 ]]; then
      printf '%s\n' "$((i + 1))"
      return 0
    fi
  done
}

# last_line_matching <file> <extended-regex> — the number of the last line of
# <file> that matches ("" when none does).
last_line_matching() {
  local -a file_lines
  local i last=""
  mapfile -t file_lines < "$1"
  for i in "${!file_lines[@]}"; do
    [[ "${file_lines[i]}" =~ $2 ]] && last=$((i + 1))
  done
  [[ -n "$last" ]] && printf '%s\n' "$last"
  return 0
}

# function_body <file> <name> — one top-level function definition of <file>:
# from its "<name>() {" line to the first line starting with "}".
function_body() {
  local line printing=0
  while IFS= read -r line; do
    [[ "$line" == "$2() {"* ]] && printing=1
    (( printing )) || continue
    printf '%s\n' "$line"
    [[ "$line" == "}"* ]] && return 0
  done < "$1"
  return 0
}
