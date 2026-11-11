# jsonc-remove.awk — remove `value` from the array whose key is `key`,
# one-line or multi-line, fixing the commas of what is left. Comments and
# formatting are kept. Exits 3 on an array that never closes.
# Used by: lib/jsonc.sh (jsonc_remove_from_array).
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
  opening = "^[[:space:]]*\"" key "\"[[:space:]]*:[[:space:]]*\\["
  if (!match($0, opening)) { print; next }
  before = substr($0, 1, RSTART + RLENGTH - 1)
  tail = substr($0, RSTART + RLENGTH)
  # One-line array: rebuild its element list without the value.
  if (match(tail, /\][^\]]*$/)) {
    after = substr(tail, RSTART)
    element_count = split(substr(tail, 1, RSTART - 1), elements, ",")
    kept_elements = ""
    for (i = 1; i <= element_count; i++) {
      element = elements[i]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", element)
      if (element == "" || element == "\"" value "\"") continue
      if (kept_elements != "") kept_elements = kept_elements ", "
      kept_elements = kept_elements element
    }
    print before kept_elements after
    next
  }
  # A multi-line array starts here.
  print
  state = 1
  item_count = 0
  next
}

# Inside a multi-line array: at its closing `]`, print the kept items with
# a comma on every one but the last, then the `]` line.
state == 1 && /^[[:space:]]*\][[:space:]]*,?[[:space:]]*$/ {
  kept_count = 0
  for (i = 1; i <= item_count; i++) {
    if (items[i] ~ "\"" value "\"") continue
    kept[++kept_count] = items[i]
  }
  for (i = 1; i <= kept_count; i++) {
    line = kept[i]
    if (i == kept_count) sub(/,[[:space:]]*$/, "", line)
    else if (line !~ /,[[:space:]]*$/) line = strip_trailing_space(line) ","
    print line
  }
  print $0
  state = 0
  item_count = 0
  next
}

# Inside a multi-line array: buffer each item line.
state == 1 { items[++item_count] = $0; next }

# The array never closed: fail rather than drop the buffered lines.
END { if (state == 1) exit 3 }
