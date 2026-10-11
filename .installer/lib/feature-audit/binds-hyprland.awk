# binds-hyprland.awk — Hyprland's Lua `hl.bind(<key expr>, hl.dsp.<disp>(…))`
# lines as `hyprland<TAB>chord<TAB>dispatch` rows (lib/feature-audit/binds.sh,
# _binds_parse_hyprland): string locals, `..` concatenation and
# `for i = a, b do … end` are evaluated (a static read of what the
# compositor would register).
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function ev(e,   n, p, i, t, o) {
  n = split(e, p, /[ \t]*\.\.[ \t]*/); o = ""
  for (i = 1; i <= n; i++) {
    t = trim(p[i])
    if (t ~ /^".*"$/) o = o substr(t, 2, length(t) - 2)
    else if (t in loc) o = o loc[t]
    else o = o t
  }
  return o
}
function chord(k,   n, p, i, t, u, o) {
  n = split(k, p, /[ \t]*\+[ \t]*/); o = ""
  for (i = 1; i <= n; i++) {
    t = trim(p[i]); u = toupper(t)
    if (u == "SUPER" || u == "MOD4" || u == "WIN") t = "Super"
    else if (u == "CTRL" || u == "CONTROL") t = "Ctrl"
    else if (u == "SHIFT") t = "Shift"
    else if (u == "ALT") t = "Alt"
    o = o (o == "" ? "" : "+") t
  }
  return o
}
function bind(s,   i, c, q, key, rest, d, disp, n) {
  sub(/^.*hl\.bind\(/, "", s)
  q = 0; key = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "\"") q = !q
    if (c == "," && !q) {
      key = substr(s, 1, i - 1); rest = substr(s, i + 1); break
    }
  }
  rest = trim(rest); sub(/^hl\.dsp\./, "", rest)
  q = 0; d = 0; disp = rest
  for (i = 1; i <= length(rest); i++) {
    c = substr(rest, i, 1)
    if (c == "\"") q = !q
    if (q) continue
    if (c == "(") d++
    if (c == ")" && --d == 0) { disp = substr(rest, 1, i); break }
  }
  for (n in loc)
    disp = gensub("\\(" n "\\)", "(\"" loc[n] "\")", "g", disp)
  printf "hyprland\t%s\t%s\n", chord(ev(key)), disp
}
/^[ \t]*--/ { next }
{ sub(/[ \t]+--[ \t].*$/, "") }
/^[ \t]*local [A-Za-z_]+[ \t]*=[ \t]*"/ {
  n = $0; sub(/^[ \t]*local[ \t]+/, "", n); v = n
  sub(/[ \t]*=.*$/, "", n); sub(/^[^"]*"/, "", v); sub(/".*$/, "", v)
  loc[n] = v; next
}
/^[ \t]*for [A-Za-z_]+[ \t]*=[ \t]*[0-9]+[ \t]*,[ \t]*[0-9]+[ \t]*do/ {
  lv = $2; a = $4; sub(/,/, "", a); b = $5
  if (b == "") { split($4, ab, ","); a = ab[1]; b = ab[2] }
  a = gensub(/[^0-9]/, "", "g", a); b = gensub(/[^0-9]/, "", "g", b)
  inl = 1; nb = 0; next
}
inl && /^[ \t]*end[ \t]*$/ {
  for (v = a + 0; v <= b + 0; v++)
    for (j = 1; j <= nb; j++)
      bind(gensub("([^A-Za-z_\"])" lv "([^A-Za-z_\"]|$)", "\\1" v "\\2",
                  "g", buf[j]))
  inl = 0; next
}
inl { if ($0 ~ /hl\.bind\(/) buf[++nb] = $0; next }
/hl\.bind\(/ { bind($0) }
