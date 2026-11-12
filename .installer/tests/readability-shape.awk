# readability-shape.awk — the Readability Lint's one-step-per-line rules
# (ADR 0167). Loaded with readability-scan.awk, which calls:
#   shape_check_command(tool, flags, line)   for every recorded command
#   shape_check_line(code, line, has_comment) once per logical line
#   shape_check_perf(raw, line)              for every physical line
#
# Rules:
#   inline-awk       awk given its program inline, not with -f <file>
#   sed-form         sed other than `sed -i 's/old/new/'`
#   pipeline-length  more than MAX_PIPES `|` in one pipeline
#   chain-length     more than MAX_CHAIN `&&` / `||` in one chain
#   program-length   an inline jq or sed program over MAX_PROGRAM
#                    characters, or one that runs onto the next line
#   what-comment     a jq, awk or sed program, or a pipeline of
#                    MAX_PIPES pipes, with no comment line directly above
#   perf-reason      a `readability-ok: perf` without a measurement

# shape_check_command(tool, flags, line) — awk and sed forms. Programs
# seen on this logical line are kept for shape_check_line().
function shape_check_command(tool, flags, line) {
  if (tool == "awk" && flags !~ / -f/) {
    emit("inline-awk", line, current_function(),
         "awk program inline: move it to a commented .awk file")
    line_has_program = 1
  }
  if (tool == "jq" && flags !~ / -f/) line_has_program = 1
  if (tool == "sed") {
    line_has_program = 1
    if (flags != " -i" || !is_one_substitution(sed_program(line_raw_text)))
      emit("sed-form", line, current_function(),
           "sed other than sed -i 's/old/new/'")
  }
}

# is_one_substitution(program) — 1 for a single `s/old/new/` (any
# delimiter, optional g). An empty program (double-quoted, so not read
# here) is given the benefit of the doubt.
function is_one_substitution(program,   delimiter, count, part) {
  if (program == "") return 1
  if (substr(program, 1, 1) != "s") return 0
  delimiter = substr(program, 2, 1)
  count = split(substr(program, 2), part, delimiter)
  return count == 4 && part[4] ~ /^g?$/
}

# sed_program(text) — the quoted program after `sed -i` in the raw logical
# line ("" when it is held in a variable: `sed -i "$edit"`).
function sed_program(text,   program) {
  if (match(text, /(^|[^A-Za-z0-9_.-])sed[ \t]+-i[ \t]+'[^']*'/)) {
    program = substr(text, RSTART, RLENGTH)
    sub(/^[^']*'/, "", program)
    sub(/'$/, "", program)
    return program
  }
  if (!match(text, /(^|[^A-Za-z0-9_.-])sed[ \t]+-i[ \t]+"[^"]*"/)) return ""
  program = substr(text, RSTART, RLENGTH)
  sub(/^[^"]*"/, "", program)
  sub(/"$/, "", program)
  # A program that is just a variable is checked where it is written.
  if (program ~ /^\$[A-Za-z_{][A-Za-z0-9_}]*$/) return ""
  return program
}

# longest_piece(text) — the longest single-quoted piece on a logical line
# (each piece ends with \001, see code_text()).
function longest_piece(text,   count, piece, n, longest) {
  longest = 0
  count = split(text, piece, "\001")
  for (n = 1; n <= count; n++)
    if (length(piece[n]) > longest) longest = length(piece[n])
  return longest
}

# count_text(text, piece) — how many times piece occurs in text.
function count_text(text, piece,   count, start) {
  count = 0
  while ((start = index(text, piece)) > 0) {
    count++
    text = substr(text, start + length(piece))
  }
  return count
}

# shape_check_line(code, line, has_comment) — pipeline and chain length,
# program length and the "what" comment, for one logical line. Returns 1
# when the line needed a "what" comment and had one: one comment covers
# a block of such lines, with no blank line between.
function shape_check_line(code, line, has_comment,   pieces, piece, count,
                          n, pipes, chains, most_pipes, needs_comment) {
  most_pipes = 0
  # Subshells and command substitutions are pipelines of their own.
  count = split(code, piece, /[();`{}]/)
  for (n = 1; n <= count; n++) {
    chains = count_text(piece[n], "&&") + count_text(piece[n], "||")
    if (chains > MAX_CHAIN)
      emit("chain-length", line, current_function(),
           chains " &&/|| in one chain (max " MAX_CHAIN ")")
    pieces = piece[n]
    gsub(/\|\|/, "", pieces)
    pipes = count_text(pieces, "|")
    if (pipes > most_pipes) most_pipes = pipes
  }
  if (most_pipes > MAX_PIPES)
    emit("pipeline-length", line, current_function(),
         most_pipes " | in one pipeline (max " MAX_PIPES ")")
  if (line_has_program &&
      (longest_piece(line_quoted_text) > MAX_PROGRAM || quote == "'"))
    emit("program-length", line, current_function(),
         "inline program over " MAX_PROGRAM " characters: name it")
  needs_comment = line_has_program || most_pipes == MAX_PIPES
  if (needs_comment && !has_comment)
    emit("what-comment", line, current_function(),
         "no comment above saying what this produces")
  line_has_program = 0
  return needs_comment && has_comment
}

function shape_check_perf(raw, line) {
  if (raw !~ /readability-ok: perf/) return
  if (raw !~ /readability-ok: perf [^ ]+ ?(→|->) ?[^ ]+/)
    emit("perf-reason", line, current_function(),
         "perf exemption needs a <before>→<after> measurement")
}

BEGIN {
  MAX_PIPES = 2
  MAX_CHAIN = 2
  MAX_PROGRAM = 40
}
