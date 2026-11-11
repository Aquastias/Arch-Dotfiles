# readability-scan.awk — the Readability Lint's scanner (ADR 0153, ADR 0167),
# driven by readability.sh. Reads shell files, prints one TSV row per finding:
#   rule <TAB> file <TAB> line <TAB> symbol <TAB> detail <TAB> strictness
#
# Shell is scanned as CODE only: a per-character state machine blanks quoted
# text and comments (quotes may span lines — multi-line awk/jq programs in
# single quotes are data, not shell), and heredoc bodies are skipped whole.
# Keyword nesting and tool calls are read from command positions only.

BEGIN {
  MAX_FUNCTION_LINES = 50
  MAX_NESTING = 3
  MAX_FILE_LINES = 500

  NAME = "[A-Za-z_][A-Za-z0-9_:.-]*"
  FOR_LOOP = "^[ \t]*for[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+in([ \t]|$)"
  FUNCTION_PARENS = "^[ \t]*(function[ \t]+)?" NAME "[ \t]*\\(\\)"
  FUNCTION_KEYWORD = "^[ \t]*function[ \t]+" NAME "[ \t]*\\{"

  # Short name tokens that are words or well-known acronyms, not shorthand.
  split("i j rc x y is to in on of by no at as if up so it or an do go me " \
        "my we us be os vm id ip ok ui qt pi jq mv cp rm ln su sh dd mb kb gb tb", \
        list, \
        " ")
  for (n in list) allowed_short[list[n]] = 1

  # Longer tokens that are shorthand a reader must decode.
  split("cfg cfgo cfgs cfgstate cfgstore ctl nav fa pw enc src dst conf " \
        "confd pkg pkgs opt opts eff topo topos esc cur sec secs num mnt " \
        "rel rels imp noc lm hist skel prog progs tok toks pos dec arr ver " \
        "tgt tgts sz svc svcs idx fn comp ca bl blcommon cnt buf fmt cands " \
        "desk pct prev priv pub ref refs recs val var vars str tmp dir dirs " \
        "msg msgs cmd cmds err errs arg args kver zver uidx aidx vdir kdir " \
        "idir hdir cpath mpath fval jval tval lkey ltype ltopo dtype dtot " \
        "dtopo dname dpool ddisk dsrc gname bpkg bsrc bdst fsrc fdst " \
        "mcur mnew peff ueff beff deff penc pcat pcell pslot bslot suuid " \
        "wpid gexec impon impen errre eopts accts asgn asg adrs bgid buid " \
        "nzroot biglist", list, " ")
  for (n in list) denied[list[n]] = 1

  # Words that may precede the real command in a segment.
  split("then do else elif ! { time exec command sudo nohup", list, " ")
  for (n in list) command_prefix[list[n]] = 1

  split("if for while until case select", list, " ")
  for (n in list) block_opener[list[n]] = 1
  split("fi done esac", list, " ")
  for (n in list) block_closer[list[n]] = 1

  load_prefix_rules()
}

# ── Prefix rule (Prefix Map, docs/agents/readability.md) ──────────────────
# The rules file lists only the map's exceptions; every other file's Prefix is
# its stem. Kinds (whitespace-separated):
#   exempt-file <glob>                   no Prefix required
#   exempt-name <glob> <function>        one frozen name (hook API)
#   interface   <function>               shared across backends
#   api         <directory/> <public>    directory API; private _<subpath>_
#   file        <glob> <public> <private>

function glob_regex(glob,   regex) {
  regex = glob
  gsub(/[.+?()^$|\[\]]/, "\\\\&", regex)
  gsub(/\*\*/, "\001", regex)
  gsub(/\*/, "[^/]*", regex)
  gsub(/\001/, ".*", regex)
  return "^" regex "$"
}

function load_prefix_rules(   row, field, count) {
  if (prefix_rules == "") return
  while ((getline row < prefix_rules) > 0) {
    sub(/#.*$/, "", row)
    count = split(row, field, /[ \t]+/)
    if (field[1] == "") { for (n = 1; n < count; n++) field[n] = field[n + 1]
                          count-- }
    if (field[1] == "exempt-file")
      exempt_file[++exempt_files] = glob_regex(field[2])
    else if (field[1] == "exempt-name") {
      exempt_name_file[++exempt_names] = glob_regex(field[2])
      exempt_name[exempt_names] = field[3]
    } else if (field[1] == "interface") interface_name[field[2]] = 1
    else if (field[1] == "api") {
      api_directory[++apis] = field[2]
      api_public[apis] = field[3]
    } else if (field[1] == "file") {
      rule_file[++file_rules] = glob_regex(field[2])
      rule_public[file_rules] = field[3]
      rule_private[file_rules] = field[4]
    }
  }
  close(prefix_rules)
}

function snake(text) {
  sub(/\.(sh|bash)$/, "", text)
  gsub(/[\/-]/, "_", text)
  return text
}

# resolve_prefix() — sets prefix_exempt, public_prefix, private_prefix and
# stem_function for the current file.
function resolve_prefix(   n, stem) {
  prefix_exempt = (FILENAME ~ /\.bats$/)
  for (n = 1; n <= exempt_files; n++)
    if (FILENAME ~ exempt_file[n]) prefix_exempt = 1
  stem = FILENAME
  sub(/^.*\//, "", stem)
  stem_function = snake(stem)
  public_prefix = stem_function "_"
  private_prefix = "_" stem_function "_"
  for (n = 1; n <= apis; n++)
    if (index(FILENAME, api_directory[n]) == 1) {
      public_prefix = api_public[n]
      private_prefix = "_" \
        snake(substr(FILENAME, length(api_directory[n]) + 1)) "_"
    }
  for (n = 1; n <= file_rules; n++)
    if (FILENAME ~ rule_file[n]) {
      public_prefix = rule_public[n]
      private_prefix = rule_private[n]
    }
}

function check_prefix(name, line,   n, want) {
  if (prefix_exempt || (name in interface_name) || name == stem_function)
    return
  for (n = 1; n <= exempt_names; n++)
    if (FILENAME ~ exempt_name_file[n] && name == exempt_name[n]) return
  want = (substr(name, 1, 1) == "_") ? private_prefix : public_prefix
  if (index(name, want) != 1)
    emit("prefix", line, name, name " (want " want "…)")
}

# emit() prints one finding; report() and strictness() live in
# readability-commands.awk.
function emit(rule, line, symbol, detail) {
  report(rule, FILENAME, line, symbol, detail)
}

function reset_file_state() {
  quote = ""          # "", "'" or "\"" — open quote carried across lines
  heredoc_end = ""    # delimiter while inside a heredoc body
  heredoc_strip = 0   # <<- form: delimiter may be tab-indented
  depth = 0           # current keyword nesting depth
  function_count = 0  # open-function stack size
  parens = 0          # open ( count, to find the end of a nested "$(…)"
  nested = 0          # "$(…)" depth inside double quotes
  heredoc_lines = 0   # heredoc body lines seen so far in this file
  open_span = ""      # closer of a span still open from an earlier line
  case_depth = 0      # open `case` blocks
  carried_code = ""   # code of a command continued with `\`
  commented_block = 0 # the line above: a program line under a "what" comment
}

# blank_span(code, opener, closer, mark) — replace each opener…closer span
# with mark. An unclosed span runs to the end of the line and sets
# span_unclosed.
function blank_span(code, opener, closer, mark,   start, rest, finish) {
  span_unclosed = 0
  while ((start = index(code, opener)) > 0) {
    rest = substr(code, start + length(opener))
    finish = index(rest, closer)
    if (finish == 0) {
      span_unclosed = 1
      return substr(code, 1, start - 1) mark
    }
    code = substr(code, 1, start - 1) mark \
      substr(rest, finish + length(closer))
  }
  return code
}

# skip_open_span(code, closer) — the code after closer, or "" when this
# line does not close the span. Clears the open-span state on a close.
function skip_open_span(code, closer) {
  if (index(code, closer) == 0) return ""
  open_span = ""
  return substr(code, index(code, closer) + length(closer))
}

# blank_non_commands(code) — hide text that looks like commands but is
# not: `[[ … ]]` tests, `(( … ))` arithmetic, array literal items and
# case patterns. The spans become one-letter marks (T, A, P). Arithmetic
# and array literals may span lines (open_span holds the closer).
function blank_non_commands(code) {
  if (open_span != "") code = skip_open_span(code, open_span)
  if (open_span != "") return ""
  code = blank_span(code, "[[", "]]", "T")
  code = blank_span(code, "((", "))", "A")
  if (span_unclosed) open_span = "))"
  gsub(/=\([^)]*\)/, "=A", code)
  if (code ~ /=\([^)]*$/) {
    sub(/=\([^)]*$/, "=A", code)
    open_span = ")"
  }
  # Inside a case body a line may start with a pattern (`start|stop)`),
  # also right after a `;;`.
  if (case_depth) {
    sub(/^[ \t]*\(?[^ \t();=]+([ \t]*\|[ \t]*[^ \t();=]+)*\)/, "P;", code)
    gsub(/;;[ \t]*\(?[^ \t();=]+([ \t]*\|[ \t]*[^ \t();=]+)*\)/, ";P;",
         code)
  }
  return code
}

function finish_file() {
  if (current_file == "") return
  if (last_line > MAX_FILE_LINES)
    report("file-length", current_file, 1, "-",
           last_line " lines (max " MAX_FILE_LINES ")")
}

# code_text(raw) — the line with quoted text replaced by Q and comments cut.
# Updates `quote` so strings spanning lines stay blanked. Also sets two
# other views of the line:
#   expansion_text      code plus double-quoted text (where ${…} expands)
#   single_quoted_text  the single-quoted text (awk and jq programs), each
#                       piece ended by \001
function code_text(raw,   out, position, char, previous) {
  out = ""
  expansion_text = ""
  single_quoted_text = ""
  previous = " "
  for (position = 1; position <= length(raw); position++) {
    char = substr(raw, position, 1)
    if (quote == "'") {
      # Each quoted piece ends with \001, so pieces stay apart.
      if (char == "'") {
        quote = ""
        out = out "Q"
        single_quoted_text = single_quoted_text "\001"
        continue
      }
      single_quoted_text = single_quoted_text char
      continue
    }
    if (quote == "\"") {
      expansion_text = expansion_text char
      if (char == "\\") { position++; continue }
      if (char == "\"") { quote = ""; out = out "Q" }
      # "$(( … ))" is arithmetic, part of the string.
      if (substr(raw, position, 3) == "$((") {
        position += 2
        if (index(substr(raw, position), "))") > 0)
          position += index(substr(raw, position), "))")
        continue
      }
      # "$( … )" is code: scan it, then resume the string at its `)`.
      if (substr(raw, position, 2) == "$(") {
        nested++
        nested_paren[nested] = parens++
        quote = ""
        out = out "Q;"
        position++
        previous = ";"
      }
      continue
    }
    if (char == "(") parens++
    if (char == ")") {
      parens--
      if (nested && parens == nested_paren[nested]) {
        nested--
        quote = "\""
        out = out ";"
        continue
      }
    }
    if (char == "\\") { out = out char substr(raw, position + 1, 1); position++
                        previous = "x"; continue }
    if (char == "'" || char == "\"") { quote = char; previous = char
                                       continue }
    if (char == "#" && previous ~ /[ \t;(|&]/) break
    out = out char
    expansion_text = expansion_text char
    previous = char
  }
  return out
}

# name_problems(name) — the abbreviated tokens in a name, space-joined.
function name_problems(name,   lowered, tokens, count, n, token, found) {
  lowered = tolower(name)
  count = split(lowered, tokens, /[_:.-]+/)
  found = ""
  for (n = 1; n <= count; n++) {
    token = tokens[n]
    if (token == "" || token ~ /^[0-9]+$/) continue
    if ((token in denied) || \
        (length(token) <= 2 && !(token in allowed_short)))
      found = found (found == "" ? "" : " ") token
  }
  return found
}

function current_function() {
  return function_count ? function_name[function_count] : "-"
}

# segments(code) — split code into command segments; fills segment[].
function segments(code,   count) {
  gsub(/&&|\|\|/, ";", code)
  gsub(/[A-Za-z0-9_.*-]+\)/, "P;", code)   # case patterns are not commands
  gsub(/[|()`]/, ";", code)
  gsub(/\$;/, ";", code)
  count = split(code, segment, ";")
  return count
}

# first_word(text) — the command word, past keyword and env prefixes.
function first_word(text,   word) {
  while (1) {
    sub(/^[ \t]+/, "", text)
    if (!match(text, /^[^ \t]+/)) return ""
    word = substr(text, 1, RLENGTH)
    if ((word in command_prefix) || word ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
      text = substr(text, RLENGTH + 1)
      continue
    }
    return word
  }
}

function check_commands(code, line, exempt,   count, n, word, peak) {
  count = segments(code)
  peak = depth
  for (n = 1; n <= count; n++) {
    word = first_word(segment[n])
    if (word in block_opener) { depth++; if (depth > peak) peak = depth }
    else if (word in block_closer) depth--
    if (word == "case") case_depth++
    else if (word == "esac" && case_depth) case_depth--
    if (exempt) continue
    commands_record(segment[n], line)
  }
  if (function_count && peak - function_base[function_count] > \
      function_peak[function_count])
    function_peak[function_count] = peak - function_base[function_count]
}

function check_locals(code, line, exempt,   rest, count, n, names, name,
                      problems) {
  if (exempt) return
  rest = ""
  if (match(code, /^[ \t]*(local|declare)([ \t]+-[A-Za-z]+)*[ \t]+/))
    rest = substr(code, RLENGTH + 1)
  else if (match(code, FOR_LOOP)) {
    rest = code
    sub(/^[ \t]*for[ \t]+/, "", rest)
    sub(/[ \t].*$/, "", rest)
  }
  if (rest == "") return
  sub(/[;&|].*$/, "", rest)          # only this declaration
  gsub(/=\([^)]*(\)|$)/, "=", rest)  # array literal values
  gsub(/\$\([^)]*\)|\$\{[^}]*\}/, "", rest)
  count = split(rest, names, /[ \t]+/)
  for (n = 1; n <= count; n++) {
    name = names[n]
    sub(/=.*$/, "", name)
    if (name !~ /^[A-Za-z_][A-Za-z0-9_]*$/) continue
    problems = name_problems(name)
    if (problems != "")
      emit("local-name", line, current_function() ":" name, name)
  }
}

# A function opening: `name() {`, `function name {`, or a bats `@test`.
function open_function(code, raw, line,   name, indent, rest, problems,
                       exempt) {
  if (match(code, /^[ \t]*@test[ \t]/)) {
    name = raw
    sub(/^[ \t]*@test[ \t]+["']/, "", name)
    sub(/["'][ \t]*\{[ \t]*$/, "", name)
    name = "@test " name
    rest = "{"
  } else if (match(code, FUNCTION_PARENS)) {
    name = substr(code, 1, RLENGTH)
    rest = substr(code, RLENGTH + 1)
    sub(/^[ \t]*(function[ \t]+)?/, "", name)
    sub(/[ \t]*\(\)$/, "", name)
  } else if (match(code, FUNCTION_KEYWORD)) {
    name = substr(code, 1, RLENGTH)
    rest = "{"
    sub(/^[ \t]*function[ \t]+/, "", name)
    sub(/[ \t]*\{$/, "", name)
  } else {
    return 0
  }
  match(code, /^[ \t]*/)
  indent = substr(code, 1, RLENGTH)
  exempt = (raw ~ /readability-ok/)
  if (name !~ /^@test /) record_function(name)

  if (name !~ /^@test / && !exempt) {
    problems = name_problems(name)
    if (problems != "") emit("function-name", line, name, problems)
    check_prefix(name, line)
  }
  # One-liner: body closes on the same line.
  if (rest ~ /\{.*\}[ \t;]*$/ || rest ~ /\{.*\}[ \t]*[<>].*$/) return 1

  function_count++
  function_name[function_count] = name
  function_start[function_count] = line
  function_heredoc_lines[function_count] = heredoc_lines
  function_indent[function_count] = indent
  function_base[function_count] = depth
  function_peak[function_count] = 0
  function_exempt[function_count] = exempt
  return 1
}

function close_function(code, line,   top, length_lines) {
  if (!function_count) return
  top = function_count
  if (code !~ ("^" function_indent[top] "\\}([ \t;<>|&]|$)")) return
  length_lines = line - function_start[top] + 1 \
    - (heredoc_lines - function_heredoc_lines[top])
  if (!function_exempt[top]) {
    if (length_lines > MAX_FUNCTION_LINES)
      emit("function-length", function_start[top], function_name[top], \
           length_lines " lines (max " MAX_FUNCTION_LINES ")")
    if (function_peak[top] > MAX_NESTING)
      emit("nesting", function_start[top], function_name[top], \
           "depth " function_peak[top] " (max " MAX_NESTING ")")
  }
  function_count--
}

FNR == 1 {
  finish_file()
  current_file = FILENAME
  reset_file_state()
  resolve_prefix()
}

{
  last_line = FNR
  raw = $0
  # Whether the line above is a comment (a "what" comment, ADR 0167).
  above_is_comment = previous_is_comment
  previous_is_comment = (raw ~ /^[ \t]*#/ && raw !~ /^[ \t]*# shellcheck/)
  # A blank line ends a block of commented program lines.
  if (raw ~ /^[ \t]*$/) commented_block = 0

  if (heredoc_end != "") {
    check_line = raw
    if (heredoc_strip) sub(/^\t+/, "", check_line)
    if (check_line == heredoc_end) heredoc_end = ""
    else heredoc_lines++   # data, not code: excluded from function length
    next
  }

  starts_in_quote = (quote != "")
  code = code_text(raw)
  # A readability-ok on a function's opening line exempts its whole body.
  exempt = (raw ~ /readability-ok/) ||
    (function_count && function_exempt[function_count])
  features_check_line(code, FNR, exempt, starts_in_quote)
  shape_check_perf(raw, FNR)

  # Heredoc opener (not a here-string): body starts on the next line.
  if (!starts_in_quote && \
      match(raw, /<<-?[ \t]*['"\\]?[A-Za-z_][A-Za-z0-9_]*/) && \
      substr(raw, RSTART, 3) != "<<<" && substr(raw, RSTART - 1, 1) != "<") {
    opener = substr(raw, RSTART, RLENGTH)
    heredoc_strip = (opener ~ /^<<-/)
    sub(/^<<-?[ \t]*['"\\]?/, "", opener)
    heredoc_end = opener
  }

  if (starts_in_quote) {
    # Continuation of a multi-line string: only the code after it closes.
    if (quote != "") next
  }

  if (open_function(code, raw, FNR)) {
    body_start = index(code, "()")
    body = blank_non_commands(substr(code, body_start ? body_start + 2 : 1))
    line_quoted_text = single_quoted_text
    line_raw_text = raw
    check_commands(body, FNR, exempt)
    if (!exempt) shape_check_line(body, FNR, above_is_comment)
    commented_block = 0
    next
  }
  close_function(code, FNR)

  # A logical line may run over several physical ones: a line ending in
  # `\`, `|`, `&&` or `||` continues on the next. The joined command is
  # checked once, at the line it started on.
  if (carried_code != "") {
    code = carried_code " " code
    exempt = exempt || carried_exempt
    command_line = carried_line
    line_quoted_text = line_quoted_text single_quoted_text
    line_raw_text = line_raw_text " " raw
  } else {
    command_line = FNR
    command_comment = above_is_comment || commented_block
    line_quoted_text = single_quoted_text
    line_raw_text = raw
  }
  if (code ~ /(\\|\||&&)[ \t]*$/) {
    sub(/\\[ \t]*$/, "", code)
    carried_code = code
    carried_line = command_line
    carried_exempt = exempt
    next
  }
  carried_code = ""
  code = blank_non_commands(code)
  check_locals(code, command_line, exempt)
  check_commands(code, command_line, exempt)
  # A lone `{` opens a group: a comment above it covers the lines inside.
  if (code ~ /^[ \t]*\{[ \t]*$/) {
    commented_block = command_comment
    next
  }
  commented_block = 0
  if (!exempt)
    commented_block = shape_check_line(code, command_line, command_comment)
}

END { finish_file() }
