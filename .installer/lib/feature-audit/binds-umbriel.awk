# binds-umbriel.awk — Umbriel's TOML `[keybinds]` (ADR 0159) as
# `umbriel<TAB>chord<TAB>action` rows (lib/feature-audit/binds.sh,
# _binds_parse_umbriel): a plain `"chord" = "action"`, an inline
# `{ action = "…", … }`, or a `[keybinds."chord"]` sub-table whose `action`
# key holds it, single-line or a `'''` multi-line literal.
function unquote(text) { gsub(/^[[:space:]"]+|["[:space:]]+$/, "", text)
  return text }
function action_of(text) {
  if (text ~ /^[[:space:]]*\{/) {
    sub(/^.*action[[:space:]]*=[[:space:]]*"/, "", text)
    sub(/".*$/, "", text); return text
  }
  return unquote(text)
}
/^[[:space:]]*#/ { next }
{ sub(/[[:space:]]+#[^"]*$/, "") }
/^[[:space:]]*\[/ {
  table = $0; gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", table)
  section = ""; chord = ""
  if (table == "keybinds") section = "plain"
  else if (table ~ /^keybinds\./) {
    section = "sub"; chord = table; sub(/^keybinds\./, "", chord)
    chord = unquote(chord)
  }
  next
}
section == "plain" && /^[[:space:]]*"/ {
  key = $0; sub(/^[[:space:]]*"/, "", key); value = key
  sub(/".*$/, "", key); sub(/^[^"]*"[[:space:]]*=[[:space:]]*/, "", value)
  printf "umbriel\t%s\t%s\n", key, action_of(value)
}
# a multi-line literal action: join its lines, a backslash-newline
# continuation becoming the one space the shell reads it as
function literal_part(text, first) {
  if (!first) sub(/^[[:space:]]+/, "", text)
  if (substr(text, length(text) - 2) == fence) {
    printf "umbriel\t%s\t%s\n", chord,
      literal substr(text, 1, length(text) - 3)
    literal = ""; open = 0; return
  }
  sub(/\\$/, "", text); literal = literal text; open = 1
}
BEGIN { fence = "\047\047\047" }
open { literal_part($0, 0); next }
section == "sub" && /^[[:space:]]*action[[:space:]]*=/ {
  value = $0; sub(/^[^=]*=[[:space:]]*/, "", value)
  sub(/[[:space:]]+$/, "", value)
  if (substr(value, 1, 3) == fence) {
    literal_part(substr(value, 4), 1); next
  }
  printf "umbriel\t%s\t%s\n", chord, unquote(value)
}
