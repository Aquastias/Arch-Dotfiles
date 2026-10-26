# lib/feature-audit/binds-emacs.awk — Doom `map!` forms → bind rows (ADR
# 0152, 0160). Prints `emacs<TAB><chord><TAB><states> <command>`: a state
# keyword (`:n`, `:m`, `:v`, `:nv`…) sets the evil states of the pairs after
# it, `:leader` makes them `SPC`-prefixed leader binds. `"key" nil` unbinds
# (no row); `:desc "…"` labels are skipped; `:map <keymap>` scopes the rest of
# the form to a mode's own keymap, which a scratch buffer cannot judge (no
# rows). Comments and strings outside a `map!` form are ignored.
# Used by: lib/feature-audit/binds.sh (_binds_parse_emacs).

# strip_comment <line> — the line before any `;` outside a string.
function strip_comment(line,    i, c, in_string) {
  for (i = 1; i <= length(line); i++) {
    c = substr(line, i, 1)
    if (in_string && c == "\\") { i++; continue }
    if (c == "\"") in_string = !in_string
    else if (c == ";" && !in_string) return substr(line, 1, i - 1)
  }
  return line
}

# take_token <token> — the map! state machine: opens/closes a form, tracks
# its states, `:leader` and `:desc`, and prints a row per `"key" #'command`.
function take_token(token) {
  if (token == "(map!") {
    in_map = 1; depth = 1; leader = 0; states = ""; pending = 0; local_map = 0
    skip_string = 0
    return
  }
  if (!in_map) return
  if (token == "(") { depth++; return }
  if (token == ")") { if (--depth == 0) in_map = 0; return }
  if (token == ":leader") { leader = 1; states = ""; return }
  if (token == ":map") { local_map = 1; return }
  if (token == ":desc") { skip_string = 1; return }
  if (token ~ /^:[nvmioer]+$/) { states = substr(token, 2); return }
  if (token ~ /^"/) {
    if (skip_string) { skip_string = 0; return }
    key = substr(token, 2, length(token) - 2); pending = 1
    return
  }
  if (token == "nil") { pending = 0; return }
  if (token ~ /^#'/ && pending && local_map) { pending = 0; return }
  if (token ~ /^#'/ && pending) {
    printf "emacs\t%s\t%s %s\n", (leader ? "SPC " key : key),
      (leader ? "leader" : states), substr(token, 3)
    pending = 0
  }
}

{
  rest = strip_comment($0)
  while (match(rest, /\(map!|"([^"\\]|\\.)*"|#'[^ \t()]+|:[a-z-]+|nil|\(|\)/)) {
    take_token(substr(rest, RSTART, RLENGTH))
    rest = substr(rest, RSTART + RLENGTH)
  }
}
