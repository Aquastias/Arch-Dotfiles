# binds-niri.awk — niri keybind parser (ADR 0152): the KDL
# `binds { Chord [props] { action; } }` blocks. Rows:
# `niri<TAB><chord><TAB><action>`, a multi-statement action `; `-joined.

# flush() — print the collected bind (its action tidied) and start a new one.
function flush() {
  gsub(/[;[:space:]]+$/, "", action)
  gsub(/^[[:space:]]+/, "", action)
  gsub(/;[[:space:]]*/, "; ", action)
  sub(/; $/, "", action)
  if (chord != "") printf "niri\t%s\t%s\n", chord, action
  chord = ""
  action = ""
}

# Drop a line comment.
{ sub(/^[[:space:]]*\/\/.*$/, "") }

# The binds block opens.
/^[[:space:]]*binds[[:space:]]*\{/ { in_binds = 1; depth = 1; next }

# Outside it: nothing to read.
!in_binds { next }

# Inside it: a chord line opens a bind; its body runs until the closing brace.
{
  line = $0
  if (depth == 1) {
    if (line ~ /^[[:space:]]*\}/) { in_binds = 0; next }
    if (line !~ /\{/) next
    split(line, words, " ")
    chord = words[1]
    sub(/^[[:space:]]+/, "", chord)
    body = line
    sub(/^[^{]*\{/, "", body)
    depth = 2
  } else body = line
  if (body ~ /\}[[:space:]]*$/) {
    sub(/\}[[:space:]]*$/, "", body)
    action = action " " body
    flush()
    depth = 1
  } else action = action " " body
}
