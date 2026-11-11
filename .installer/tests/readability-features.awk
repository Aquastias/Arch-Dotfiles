# readability-features.awk — the Readability Lint's Bash Feature Tier and
# jq feature checks (ADR 0167). Loaded with readability-scan.awk, which
# calls:
#   features_check_line(code, line, exempt, starts_in_quote)
#                          for every line, right after code_text()
#   features_check_command(tool, flags, line)
#                          for every command it records
#
# Banned bash: `${!name}`, namerefs (`declare -n`, `local -n`), `eval`,
# `<<<`, `BASH_REMATCH`, pattern operators in `${…}` (`#`, `##`, `%`,
# `%%`, `/`, `//`, `^`, `,`, `@`), `printf -v`. The one allowed pattern
# operator is the bootstrap line that finds a script's own directory.
#
# Banned jq: reduce, foreach, walk, def, paths, getpath, setpath, inputs.
# They are looked for in the single-quoted text of a line that calls jq,
# including a program that continues over the next lines. A program kept
# in a variable or a `.jq` file is not checked here.

# bash_feature(line, detail) — report one banned bash feature.
function bash_feature(line, detail) {
  emit("bash-feature", line, current_function(), detail \
       " is banned (Bash Feature Tier)")
}

# check_expansions(line) — banned `${…}` forms in code and double-quoted
# text (expansion_text, set by code_text()).
function check_expansions(line,   text) {
  text = expansion_text
  # The bootstrap line: a script finding its own directory.
  gsub(/\$\{(script_path|BASH_SOURCE\[0\])%\/\*\}/, "", text)
  if (text ~ /\$\{![A-Za-z_][A-Za-z0-9_]*\}/)
    bash_feature(line, "${!name} indirection")
  if (text ~ PATTERN_OPERATOR)
    bash_feature(line, "a ${…} pattern operator (#, %, /, ^, ,, @)")
  if (text ~ /BASH_REMATCH/)
    bash_feature(line, "BASH_REMATCH")
}

# check_jq_program(line) — banned jq features in this line's
# single-quoted text.
function check_jq_program(line,   n) {
  for (n = 1; n <= jq_banned_count; n++)
    if (single_quoted_text ~ jq_banned_regex[n])
      emit("jq-feature", line, current_function(),
           "jq " jq_banned[n] " is banned (ADR 0167)")
}

function features_check_line(code, line, exempt, starts_in_quote) {
  # A jq program that started on an earlier line.
  if (starts_in_quote) {
    if (jq_program_open && !exempt) check_jq_program(line)
    if (quote == "") jq_program_open = 0
    return
  }
  if (exempt) return
  check_expansions(line)
  if (index(code, "<<<") > 0) bash_feature(line, "the <<< here-string")
  if (code ~ /(^|[^A-Za-z0-9_.-])jq([ \t]|$)/) {
    check_jq_program(line)
    jq_program_open = (quote == "'")
  }
}

# features_check_command(tool, flags, line) — banned commands and flags.
function features_check_command(tool, flags, line) {
  if (tool == "eval") bash_feature(line, "eval")
  if (tool ~ /^(local|declare|typeset|readonly)$/ && flags ~ / -[A-Za-z]*n/)
    bash_feature(line, "a nameref (" tool " -n)")
  if (tool == "printf" && flags ~ / -v/) bash_feature(line, "printf -v")
}

BEGIN {
  # A `${name` (or `${name[…]`, `${1`, `${@`) followed by an operator.
  PATTERN_OPERATOR = "\\$\\{([A-Za-z_][A-Za-z0-9_]*|[0-9]+|@|\\*)" \
    "(\\[[^]]*\\])?(#|%|/|\\^|,|@)"

  jq_banned_count = split("reduce foreach walk def paths getpath setpath " \
                          "inputs", jq_banned, " ")
  for (n = 1; n <= jq_banned_count; n++)
    jq_banned_regex[n] = "(^|[^A-Za-z0-9_$.])" jq_banned[n] \
      "([^A-Za-z0-9_]|$)"
}
