# readability-commands.awk — the Readability Lint's command and flag checks
# (ADR 0167). Loaded together with readability-scan.awk, which calls:
#   commands_record(segment, line)  for every command segment it reads
#   commands_finish()               once, after the last file
#
# The Tool Reference doc is the allowlist. A command used at command
# position must have a heading there, and each flag it is given must be
# listed under that heading. A word is skipped when it names a function
# defined in any scanned file, a script path, or a variable.
#
# Findings are reported at the end, because a function may be defined in
# a file read after the one that calls it.
#
# Inputs (awk -v):
#   tool_reference   path of the Tool Reference doc ("" = no doc)
#   migrated_areas   path of the Migrated Areas list ("" = none)

# load_tool_reference() — read the Tool Reference doc.
#
# A tool is a heading holding one backticked name:
#   ### `cut`
# Its flags are the bullets below it that start with backticked flags.
# A flag followed by a <placeholder> takes a value:
#   - `-d <delimiter>` — the character between fields
#   - `-r`, `--raw-output` — print strings without quotes
# Fills reference_tool[tool], reference_flag[tool, flag] and
# reference_value[tool, flag].
function load_tool_reference(   row, tool, rest, token, flag) {
  if (tool_reference == "") return
  tool = ""
  in_fence = 0
  while ((getline row < tool_reference) > 0) {
    # Code blocks show examples; they declare nothing.
    if (row ~ /^```/) in_fence = !in_fence
    if (in_fence || row ~ /^```/) continue
    # A new heading ends the previous tool's flag list.
    if (row ~ /^#/) tool = ""
    if (row ~ /^###? `[^`]+`[ \t]*$/) {
      tool = row
      sub(/^###? `/, "", tool)
      sub(/`[ \t]*$/, "", tool)
      reference_tool[tool] = 1
      continue
    }
    if (tool == "" || row !~ /^- `-/) continue
    rest = substr(row, 3)
    # Read each `-flag` token at the start of the bullet.
    while (match(rest, /^`[^`]+`/)) {
      token = substr(rest, 2, RLENGTH - 2)
      rest = substr(rest, RLENGTH + 1)
      sub(/^, /, "", rest)
      if (token !~ /^-/) break
      flag = token
      sub(/[ \t].*$/, "", flag)
      reference_flag[tool, flag] = 1
      if (token ~ /[ \t]/) reference_value[tool, flag] = 1
    }
  }
  close(tool_reference)
}

# load_migrated_areas() — read the Migrated Areas list: one glob per line,
# `#` comments. Fills migrated_glob[1..migrated_globs].
function load_migrated_areas(   row) {
  if (migrated_areas == "") return
  while ((getline row < migrated_areas) > 0) {
    sub(/#.*$/, "", row)
    gsub(/[ \t]/, "", row)
    if (row != "") migrated_glob[++migrated_globs] = glob_regex(row)
  }
  close(migrated_areas)
}

# is_migrated(file) — 1 when the file is in a Migrated Area.
function is_migrated(file,   n) {
  for (n = 1; n <= migrated_globs; n++)
    if (file ~ migrated_glob[n]) return 1
  return 0
}

# strictness(rule, file) — "strict" or "advisory". ADR 0153 rules stay
# strict inside .installer/; every other finding is advisory until its
# file's area is migrated.
function strictness(rule, file) {
  if (is_migrated(file)) return "strict"
  if ((rule in legacy_rule) && file ~ /^\.installer\//) return "strict"
  return "advisory"
}

# is_command_word(word) — 1 when the word can name a command to look up.
# Paths, repo scripts, variables, quoted text (Q) and redirections are not.
function is_command_word(word) {
  if (word ~ /^Q+$/ || word == "P" || word == "A" || word == "T") return 0
  if (word ~ /\//) return 0
  if (word ~ /\.(sh|bash|awk|bats)$/) return 0
  if (word == "[" || word == "." || word == ":") return 1
  return word ~ /^[A-Za-z_][A-Za-z0-9_.+-]*$/
}

# is_wrapper(tool) — 1 when the tool runs the command written after it.
# bats' `run` only wraps inside .bats files.
function is_wrapper(tool) {
  if (tool == "run") return FILENAME ~ /\.bats$/
  return tool in wrapper_command
}

# commands_record(text, line) — record each command in one segment.
# Wrapper commands (sudo, timeout, env, …) run another command; the
# wrapped command is recorded too.
function commands_record(text, line,   words, word, count, position, tool,
                         flags) {
  count = split(text, word, /[ \t]+/)
  position = 1
  while (position <= count) {
    # `for name in …`, `select …` and `case word in` hold no command.
    if (word[position] ~ /^(for|select|case)$/) return
    # Skip empty words, keywords and VAR=value prefixes.
    if (word[position] == "" || (word[position] in shell_keyword) ||
        word[position] ~ /^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=/) {
      position++
      continue
    }
    tool = word[position]
    if (!is_command_word(tool)) return
    position++
    flags = ""
    if (!is_wrapper(tool)) {
      # Every dash word up to `--` is a flag of this command. A shell's
      # flags end at the script name: what follows is the script's.
      for (; position <= count; position++) {
        if (word[position] == "--") break
        if ((tool in shell_command) && word[position] !~ /^-/) break
        if (tool == "find" && word[position] ~ /^-(exec|execdir|ok)$/) {
          flags = flags " " word[position]
          position++
          break
        }
        if (word[position] ~ /^-./) flags = flags " " word[position]
      }
      save_use(tool, flags, line)
      if (tool != "find") return
      continue
    }
    # A wrapper's own flags come first; the next plain word is the
    # wrapped command (after one duration for `timeout`).
    for (; position <= count && word[position] ~ /^-./; position++) {
      flags = flags " " word[position]
      if ((tool, word[position]) in reference_value) position++
    }
    save_use(tool, flags, line)
    if (tool == "command" && flags ~ /-[vV]/) return
    if (tool == "timeout") position++
  }
}

# record_function(name) — remember a function defined in this file.
# Test files often stub real commands (`systemctl() { :; }`), so a
# function defined under tests/ only hides the command inside tests.
function record_function(name) {
  file_function[FILENAME, name] = 1
  if (is_test_file(FILENAME)) test_function[name] = 1
  else library_function[name] = 1
}

function is_test_file(file) {
  return file ~ /^\.installer\/tests\//
}

# is_function_call(tool, file) — 1 when the word calls a repo function
# rather than a command.
function is_function_call(tool, file) {
  if ((file, tool) in file_function) return 1
  if (tool in library_function) return 1
  return is_test_file(file) && (tool in test_function)
}

# save_use(tool, flags, line) — keep one command use for commands_finish().
function save_use(tool, flags, line) {
  uses++
  use_tool[uses] = tool
  use_flags[uses] = flags
  use_file[uses] = FILENAME
  use_line[uses] = line
  use_function[uses] = current_function()
  features_check_command(tool, flags, line)
  shape_check_command(tool, flags, line)
}

# flag_problems(tool, flag) — the flag word when the Tool Reference
# does not list it ("" when it does). A cluster like `-rf`
# is read one letter at a time; a letter that takes a value ends it.
function flag_problems(tool, flag,   position, letter) {
  sub(/=.*$/, "", flag)
  if ((tool, flag) in reference_flag) return ""
  if (flag ~ /^--/ || flag !~ /^-[A-Za-z0-9]/) return flag
  for (position = 2; position <= length(flag); position++) {
    letter = "-" substr(flag, position, 1)
    if (!((tool, letter) in reference_flag)) return flag
    if ((tool, letter) in reference_value) return ""
  }
  return ""
}

# report() — print one finding as TSV: rule, file, line, symbol, detail,
# strictness.
function report(rule, file, line, symbol, detail) {
  printf "%s\t%s\t%d\t%s\t%s\t%s\n", rule, file, line, symbol, detail, \
    strictness(rule, file)
}

function commands_finish(   n, tool, count, flag, problem, f) {
  for (n = 1; n <= uses; n++) {
    tool = use_tool[n]
    if (is_function_call(tool, use_file[n])) continue
    if (!(tool in reference_tool)) {
      report("tool-reference", use_file[n], use_line[n],
             use_function[n] ":" tool, tool " has no Tool Reference entry")
      continue
    }
    count = split(use_flags[n], flag, " ")
    for (f = 1; f <= count; f++) {
      problem = flag_problems(tool, flag[f])
      if (problem != "")
        report("flag-reference", use_file[n], use_line[n],
               use_function[n] ":" tool, tool " " problem \
               " has no Tool Reference entry")
    }
  }
}

BEGIN {
  split("if then else elif fi for while until do done case esac in " \
        "select function time ! { } [[ ]] coproc", list, " ")
  for (n in list) shell_keyword[list[n]] = 1

  # Commands that run the command written after them.
  split("sudo exec command nohup env timeout xargs", list, " ")
  for (n in list) wrapper_command[list[n]] = 1
  split("bash sh zsh", list, " ")
  for (n in list) shell_command[list[n]] = 1

  # ADR 0153 rules: strict inside .installer/ before any migration.
  split("function-name local-name function-length nesting file-length " \
        "prefix", list, " ")
  for (n in list) legacy_rule[list[n]] = 1

  load_tool_reference()
  load_migrated_areas()
}

END { commands_finish() }
