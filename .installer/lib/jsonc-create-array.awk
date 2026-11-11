# jsonc-create-array.awk — add `"key": ["value"]` as the first member of the
# object `parent`, when that object opens on its own line (a profile with
# no persist.files yet). Comments and formatting are kept.
# Used by: lib/jsonc.sh (jsonc_append_to_array).
# Variables (awk -v): parent, key, value.

# The line after the parent's opening line: write the new member first,
# with a comma unless the object closes right away.
pending {
  separator = ($0 ~ /^[[:space:]]*}/) ? "" : ","
  print indent "\"" key "\": [\"" value "\"]" separator
  pending = 0
}

# Every line is kept.
{ print }

# The parent object's opening line (`"parent": {`): remember its indent,
# one level deeper, for the member written on the next line.
$0 ~ "^[[:space:]]*\"" parent "\"[[:space:]]*:" && $0 ~ /\{[[:space:]]*$/ {
  match($0, /^[[:space:]]*/)
  indent = substr($0, 1, RLENGTH) "  "
  pending = 1
}
