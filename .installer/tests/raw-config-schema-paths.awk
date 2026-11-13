# raw-config-schema-paths.awk — the jq path of each `"name|path|type|default"`
# row of _INSTALL_CONFIG_SCHEMA, one per line. A row split across lines as
# `"a|"\` + `"b"` is joined first. With -v escape=1 each path is printed as an
# ERE literal (`.` `[` `]` backslashed).

# The array opens: start reading rows.
/^_INSTALL_CONFIG_SCHEMA=\(/ { inside = 1; next }

# The array closes: done.
inside && /^\)/ { exit }

# A comment inside the array.
inside && /^[[:space:]]*#/ { next }

# The first half of a split row: hold it for the next line.
inside && /"\\$/ { held = held $0; next }

# A whole row: join the halves, then print its second field.
inside {
  row = held $0; held = ""
  gsub(/"\\[[:space:]]*"/, "", row)
  if (!match(row, /"[^"]*"/)) next
  split(substr(row, RSTART + 1, RLENGTH - 2), field, "|")
  if (field[2] == "") next
  if (escape) gsub(/[.[\]]/, "\\\\&", field[2])
  print field[2]
}
