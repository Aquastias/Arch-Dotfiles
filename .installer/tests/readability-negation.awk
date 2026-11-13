# readability-negation.awk — the Readability Lint's negated-assertion rule
# for bats files. Loaded FIRST, before readability-scan.awk: the scanner's
# rules end with `next`, so a module after it would not see every line.
#
# Rule:
#   negated-assertion  a `! cmd` line in a @test body that is not the body's
#                      last command and has no `||` after it. bash's set -e
#                      ignores a negated command, so the line can never fail
#                      the test. Write `! cmd || return 1`, or `run cmd` and
#                      check "$status".
#
# Reads raw lines: a @test body runs from its `@test` line to the `}` in
# column one. A command continued with `\` is read as one.

# negation_finish() — report the open test's non-final, unguarded `! cmd`
# commands, then close it.
function negation_finish(   n) {
  if (!negation_open) return
  for (n = 1; n < negation_count; n++) {
    if (negation_command[n] !~ /^[[:space:]]*! /) continue
    if (negation_command[n] ~ /\|\||readability-ok/) continue
    report("negated-assertion", negation_file, negation_line[n], "",
           "! cmd that is not the test's last line never fails it:" \
           " add || return 1")
  }
  negation_open = 0
}

# A new file: close the last file's open test.
FNR == 1 { negation_finish() }

# A @test line opens a body.
FILENAME ~ /\.bats$/ && /^@test / {
  negation_finish()
  negation_open = 1
  negation_file = FILENAME
  negation_count = 0
  negation_continued = 0
}

# Inside a body: collect its commands (a continued line joins the last one);
# the closing brace reports and closes.
negation_open && !/^@test / {
  if (/^}/) negation_finish()
  else if (negation_continued) {
    negation_command[negation_count] = negation_command[negation_count] " " $0
    negation_continued = /\\$/
  } else if (!/^[[:space:]]*(#|$)/) {
    negation_command[++negation_count] = $0
    negation_line[negation_count] = FNR
    negation_continued = /\\$/
  }
}

# The last file's open test.
END { negation_finish() }
