# jsonc-append.awk — append `value` to the array whose key is `key`,
# keeping comments and formatting:
#   - an empty one-line array (`"key": []`) grows to three lines,
#   - a one-line array gains `, "value"` before its `]`,
#   - a multi-line array gets a new last line (the old last element gains
#     a comma).
# Exits 3 when the array never closes on its own line (every buffered line
# would be lost).
# Used by: lib/jsonc.sh (jsonc_append_to_array).
# Variables (awk -v): key, value.
#
# state 0: looking for the array's opening line.
# state 1: inside a multi-line array; its item lines are buffered in
#          items[] until the closing `]` line.

function strip_trailing_space(text) {
  sub(/[[:space:]]+$/, "", text)
  return text
}

BEGIN { state = 0; item_count = 0 }

# Before the array: find its opening line, `"key": [`.
state == 0 {
  opening = "^([[:space:]]*)\"" key "\"[[:space:]]*:[[:space:]]*\\["
  if (!match($0, opening)) { print; next }
  open_start = RSTART
  open_length = RLENGTH
  match($0, /^[[:space:]]*/)
  base_indent = substr($0, 1, RLENGTH)
  item_indent = base_indent "  "
  tail = substr($0, open_start + open_length)
  sub(/^[[:space:]]+/, "", tail)
  # Empty one-line array: open it onto three lines with the value inside.
  if (tail ~ /^\][[:space:]]*,?[[:space:]]*$/) {
    trailing_comma = (tail ~ /\][[:space:]]*,/) ? "," : ""
    print substr($0, 1, open_start + open_length - 1)
    print item_indent "\"" value "\""
    print base_indent "]" trailing_comma
    next
  }
  # One-line non-empty array: insert before its closing bracket.
  if (match($0, /\][^\]]*$/)) {
    before = strip_trailing_space(substr($0, 1, RSTART - 1))
    print before ", \"" value "\"" substr($0, RSTART)
    next
  }
  # A multi-line array starts here.
  print
  state = 1
  item_count = 0
  next
}

# Inside a multi-line array: at its closing `]`, print the buffered items
# (the last one gains a comma), then the value, then the `]` line.
state == 1 && /^[[:space:]]*\][[:space:]]*,?[[:space:]]*$/ {
  for (i = 1; i <= item_count; i++) {
    line = items[i]
    if (i == item_count && line !~ /,[[:space:]]*$/)
      line = strip_trailing_space(line) ","
    print line
  }
  # The new item takes the indent of the first item (or one level in).
  if (item_count > 0) {
    match(items[1], /^[[:space:]]*/)
    indent = substr(items[1], 1, RLENGTH)
  } else {
    indent = item_indent
  }
  print indent "\"" value "\""
  print $0
  state = 0
  next
}

# Inside a multi-line array: buffer each item line.
state == 1 { items[++item_count] = $0; next }

# The array never closed: fail rather than drop the buffered lines.
END { if (state == 1) exit 3 }
