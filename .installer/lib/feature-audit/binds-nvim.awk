# lib/feature-audit/binds-nvim.awk — nvim keymap parser (ADR 0152)
# Whole-file read (RS="^$"). Rows: `nvim<TAB><lhs><TAB><modes> <desc>`.
# Covers map()/vim.keymap.set() calls (mode string/table first, or a local
# `map(lhs, fn, desc)` wrapper) and lazy.nvim `keys = { { "lhs", … } }`
# specs. A dynamically built lhs (`"<leader>" .. i`) is skipped: the live
# probe's keymap dump plans those.
function emit(mode, lhs, desc) {
  gsub(/"/, "", lhs)
  if (lhs == "") return
  printf "nvim\t%s\t%s %s\n", lhs, mode, desc
}
# modes_of("n" | { "n", "t" }) → "n" | "n,t"
function modes_of(s,   out, n, i, t) {
  n = split(s, t, /"/); out = ""
  for (i = 2; i <= n; i += 2) out = out (out == "" ? "" : ",") t[i]
  return out
}
# str_of(text, key) → the "…" value of `key = "…"` in text, or ""
function str_of(text, key,   v) {
  if (!match(text, key "[[:space:]]*=[[:space:]]*\"[^\"]*\"")) return ""
  v = substr(text, RSTART, RLENGTH)
  sub(/^[^"]*"/, "", v); sub(/"$/, "", v)
  return v
}
# first_str(text) → the first "…" literal after a comma, or ""
function first_str(text,   v) {
  if (!match(text, /^[^,]*,[[:space:]]*"[^"]*"/)) return ""
  v = substr(text, RSTART, RLENGTH)
  sub(/^[^"]*"/, "", v); sub(/"$/, "", v)
  return v
}
BEGIN {
  RS = "^$"
  CALL = "(map|vim\\.keymap\\.set)\\([[:space:]]*(\\{[^}]*\\}|\"[^\"]*\")" \
         "[[:space:]]*,[[:space:]]*(\"[^\"]*\")?"
}
{
  txt = $0
  gsub(/--[^\n]*/, "", txt)            # lua line comments

  # 1) map / vim.keymap.set calls
  s = txt
  while (match(s, CALL, m)) {
    a1 = m[2]; a2 = m[3]; adv = RSTART + RLENGTH
    rest = substr(s, adv, 400)
    if (rest ~ /^[[:space:]]*\.\./) { s = substr(s, adv); continue }
    d = str_of(rest, "desc")
    if (a1 ~ /^\{/ || a1 ~ /^"[nvxsoictl]+"$/) {
      if (a2 != "") emit(modes_of(a1), a2, d)
    } else {
      # wrapper map("lhs", fn, "desc"): mode defaults to n
      if (d == "") d = first_str(rest)
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
      if (c == "\"") {                 # copy a whole string literal
        j = index(substr(s, i + 1), "\"")
        if (j == 0) { i = length(s); break }
        if (depth >= 2) ent = ent substr(s, i, j + 1)
        i += j; continue
      }
      if (c == "{") {
        depth++
        if (depth == 2) ent = ""; else if (depth > 2) ent = ent c
        continue
      }
      if (c == "}") {
        depth--
        if (depth == 1) key_entry(ent)
        else if (depth > 1) ent = ent c
        continue
      }
      if (depth >= 2) ent = ent c
    }
    s = substr(s, i)
  }
}
# key_entry(ent) — one `{ "lhs", …, mode = …, desc = … }` spec
function key_entry(ent,   lhs, md, mm) {
  lhs = ent; sub(/^[^"]*"/, "", lhs); sub(/".*$/, "", lhs)
  md = "n"
  if (match(ent, /mode[[:space:]]*=[[:space:]]*(\{[^}]*\}|"[^"]*")/)) {
    mm = substr(ent, RSTART, RLENGTH)
    sub(/^mode[[:space:]]*=[[:space:]]*/, "", mm)
    md = modes_of(mm)
  }
  emit(md, "\"" lhs "\"", str_of(ent, "desc"))
}
