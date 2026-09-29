# lib/feature-audit/binds-nvim.awk — nvim keymap parser (ADR 0152)
# Whole-file read (RS="^$"). Rows: `nvim<TAB><lhs><TAB><modes> <desc>`.
# Covers map()/vim.keymap.set() calls (mode string/table first, or a local
# `map(lhs, fn, desc)` wrapper) and lazy.nvim `keys = { { "lhs", … } }`
# specs. A dynamically built lhs (`"<leader>" .. i`) is skipped: the live
# probe's keymap dump reports those as untested binds.
function emit(mode, lhs, desc) {
  gsub(/"/, "", lhs)
  if (lhs == "") return
  printf "nvim\t%s\t%s %s\n", lhs, mode, desc
}
function modes_of(s,   m, out, n, i, t) {
  # s: "n" or { "n", "t" }
  n = split(s, t, /"/); out = ""
  for (i = 2; i <= n; i += 2) out = out (out == "" ? "" : ",") t[i]
  return out
}
BEGIN { RS = "^$" }
{
  txt = $0
  gsub(/--[^\n]*/, "", txt)            # lua line comments
  # 1) map / vim.keymap.set calls
  s = txt
  while (match(s, /(map|vim\.keymap\.set)\([[:space:]]*(\{[^}]*\}|"[^"]*")[[:space:]]*,[[:space:]]*("[^"]*")?/, m)) {
    a1 = m[2]; a2 = m[3]; adv = RSTART + RLENGTH
    rest = substr(s, adv, 400)
    if (rest ~ /^[[:space:]]*\.\./) { s = substr(s, adv); continue }
    d = ""; if (match(rest, /desc[[:space:]]*=[[:space:]]*"[^"]*"/)) { d = substr(rest, RSTART, RLENGTH); sub(/^[^"]*"/, "", d); sub(/"$/, "", d) }
    if (a1 ~ /^\{/ || a1 ~ /^"[nvxsoictl]+"$/) {
      if (a2 != "") emit(modes_of(a1), a2, d)
    } else {
      # wrapper map("lhs", fn, "desc"): mode defaults to n
      if (d == "" && match(rest, /^[^,]*,[[:space:]]*"[^"]*"/)) { d = substr(rest, RSTART, RLENGTH); sub(/^[^"]*"/, "", d); sub(/"$/, "", d) }
      emit("n", a1, d)
    }
    s = substr(s, adv)
  }
  # 2) lazy.nvim `keys = { { "lhs", ..., mode = ..., desc = ... }, ... }`
  s = txt
  while (match(s, /keys[[:space:]]*=[[:space:]]*\{/)) {
    s = substr(s, RSTART + RLENGTH); depth = 1; ent = ""
    for (i = 1; i <= length(s) && depth > 0; i++) {
      c = substr(s, i, 1)
      if (c == "\"") { j = index(substr(s, i + 1), "\""); if (j == 0) { i = length(s); break }
        if (depth >= 2) ent = ent substr(s, i, j + 1); i += j; continue }
      if (c == "{") { depth++; if (depth == 2) ent = ""; else if (depth > 2) ent = ent c; continue }
      if (c == "}") {
        depth--
        if (depth == 1) {
          lhs = ent; sub(/^[^"]*"/, "", lhs); sub(/".*$/, "", lhs)
          md = "n"; if (match(ent, /mode[[:space:]]*=[[:space:]]*(\{[^}]*\}|"[^"]*")/)) { mm = substr(ent, RSTART, RLENGTH); sub(/^mode[[:space:]]*=[[:space:]]*/, "", mm); md = modes_of(mm) }
          d = ""; if (match(ent, /desc[[:space:]]*=[[:space:]]*"[^"]*"/)) { d = substr(ent, RSTART, RLENGTH); sub(/^[^"]*"/, "", d); sub(/"$/, "", d) }
          emit(md, "\"" lhs "\"", d)
        } else if (depth > 1) ent = ent c
        continue
      }
      if (depth >= 2) ent = ent c
    }
    s = substr(s, i)
  }
}
