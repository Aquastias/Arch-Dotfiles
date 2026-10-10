# readability-scan.awk — the Readability Lint's scanner (ADR 0153), driven by
# readability.sh. Reads shell files, prints one TSV row per violation:
#   rule <TAB> file <TAB> line <TAB> symbol <TAB> detail
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

  # Replace-tier tools (Tool Tiers): rewrite with jq/awk/grep or a builtin.
  split("cut tr head tail wc paste comm uniq column bc xargs realpath " \
        "basename dirname", list, " ")
  for (n in list) replace_tier[list[n]] = 1

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

function emit(rule, line, symbol, detail) {
  printf "%s\t%s\t%d\t%s\t%s\n", rule, FILENAME, line, symbol, detail
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
}

function finish_file() {
  if (current_file == "") return
  if (last_line > MAX_FILE_LINES)
    printf "%s\t%s\t%d\t%s\t%s\n", "file-length", current_file, 1, "-", \
      last_line " lines (max " MAX_FILE_LINES ")"
}

# code_text(raw) — the line with quoted text replaced by Q and comments cut.
# Updates `quote` so strings spanning lines stay blanked.
function code_text(raw,   out, position, char, previous) {
  out = ""
  previous = " "
  for (position = 1; position <= length(raw); position++) {
    char = substr(raw, position, 1)
    if (quote == "'") {
      if (char == "'") { quote = ""; out = out "Q" }
      continue
    }
    if (quote == "\"") {
      if (char == "\\") { position++; continue }
      if (char == "\"") { quote = ""; out = out "Q" }
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
    if (exempt) continue
    if (word in replace_tier)
      emit("tool", line, current_function() ":" word, word)
    else if (word == "sed" && \
             segment[n] !~ /(^|[ \t])(-[A-Za-z]*i[A-Za-z.]*|--in-place)/)
      emit("sed-not-inplace", line, current_function() ":sed", \
           "sed without -i")
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

  if (heredoc_end != "") {
    check_line = raw
    if (heredoc_strip) sub(/^\t+/, "", check_line)
    if (check_line == heredoc_end) heredoc_end = ""
    else heredoc_lines++   # data, not code: excluded from function length
    next
  }

  starts_in_quote = (quote != "")
  code = code_text(raw)
  exempt = (raw ~ /readability-ok/)

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
    check_commands(substr(code, body_start ? body_start + 2 : 1), \
                   FNR, exempt)
    next
  }
  close_function(code, FNR)
  check_locals(code, FNR, exempt)
  check_commands(code, FNR, exempt)
}

END { finish_file() }
