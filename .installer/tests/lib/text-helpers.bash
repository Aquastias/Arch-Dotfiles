#!/usr/bin/env bash
# tests/lib/text-helpers.bash — text assertions shared by the bats suites
# (ADR 0167). Used by: bats files that `load` it (lib/text-helpers from
# tests/, ../lib/text-helpers from a subdirectory).
#
#   output_has_line <line>        — one line of $output is exactly <line>
#   text_has_line <text> <line>   — one line of <text> is exactly <line>
#   tree_has [-E -i -w] <re> <path>… — a file under <path>… has a matching line
#   lines_between <start> <end>   — stdin's lines from <start> to <end> (sed /a/,/b/)
#   join_continued <file>         — <file> with backslash-continued lines joined
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

# text_has_line <text> <line> — 0 when one line of <text> is exactly <line>.
text_has_line() {
  local line
  while IFS= read -r line; do
    [[ "$line" == "$2" ]] && return 0
  done < <(printf '%s\n' "$1")
  return 1
}

# tree_has [-E] [-i] [-w] <pattern> <path>… — 0 when a line of any file under
# <path>… matches <pattern> (grep's flags: -E extended, -i any case, -w whole
# words). Stands in for `grep -r`: ADR 0167 keeps grep to one file at a time.
tree_has() {
  local -a flags=()
  local pattern match
  while [[ "$1" == -? ]]; do
    flags+=("$1")
    shift
  done
  pattern="$1"
  shift
  # The first file holding a matching line.
  match="$(find "$@" -type f -exec grep -q "${flags[@]}" -- "$pattern" {} \; \
    -print -quit 2>/dev/null)"
  [[ -n "$match" ]]
}

# lines_between <start-ERE> <end-ERE> — stdin's lines from each one matching
# <start> through the next one after it matching <end> (sed's /a/,/b/p).
lines_between() {
  local line inside=0
  while IFS= read -r line; do
    if (( inside )); then
      printf '%s\n' "$line"
      [[ "$line" =~ $2 ]] && inside=0
    elif [[ "$line" =~ $1 ]]; then
      printf '%s\n' "$line"
      inside=1
    fi
  done
  return 0
}

# join_continued <file> — <file> with each backslash-ended line joined to the
# next one (the backslash dropped).
join_continued() {
  local line joined=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == *\\ ]]; then
      joined+="${line:0:${#line}-1}"
    else
      printf '%s\n' "${joined}${line}"
      joined=""
    fi
  done < "$1"
  [[ -z "$joined" ]] || printf '%s\n' "$joined"
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
