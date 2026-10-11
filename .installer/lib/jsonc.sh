#!/usr/bin/env bash
# =============================================================================
# lib/jsonc.sh — JSONC parsing primitives
# =============================================================================
# Pure — no dependencies, no error() calls.
# Sourced by lib/common.sh and lib/config/program-registry.sh.
# =============================================================================

# jsonc_strip FILE → strips // line-comments, emits plain JSON on stdout.
jsonc_strip() {
  awk '
    { sub(/[[:space:]]*\/\/$/, "")
      sub(/[[:space:]]\/\/[^"]*$/, "") }
    /^[[:space:]]*\/\// { next }
    { print }
  ' "$1" 2>/dev/null
}

# jsonc FILE → alias for jsonc_strip; retained for callers predating the rename.
jsonc() { jsonc_strip "$1"; }

# jsonc_read FILE PATH → raw jq read; jq null for missing fields.
jsonc_read() { jsonc_strip "$1" | jq -r "$2"; }

# jsonc_read_optional FILE PATH → empty string if field is missing or null.
jsonc_read_optional() { jsonc_strip "$1" | jq -r "$2 // empty"; }

# ── Array edits that keep comments and formatting ──────────────────────────
# The edits are line-oriented awk programs, kept as named constants so the
# shell functions below read as the steps they take.

# Appends `value` to the array whose key is `key`: an empty one-line array
# grows to three lines, a one-line array gains `, "value"` before its `]`, and a
# multi-line array gets a new last line (the old last element gains a comma).
# Exits 3 when the array never closes on its own line (every buffered line
# would be lost).
# shellcheck disable=SC2016 # an awk program, not shell
_JSONC_APPEND_PROGRAM='
  function strip_trailing_space(text) {
    sub(/[[:space:]]+$/, "", text); return text
  }
  BEGIN { state = 0; item_count = 0 }
  state == 0 {
    opening = "^([[:space:]]*)\"" key "\"[[:space:]]*:[[:space:]]*\\["
    if (match($0, opening)) {
      open_start = RSTART; open_length = RLENGTH
      match($0, /^[[:space:]]*/); base_indent = substr($0, 1, RLENGTH)
      item_indent = base_indent "  "
      tail = substr($0, open_start + open_length)
      sub(/^[[:space:]]+/, "", tail)
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
      print; state = 1; item_count = 0; next
    }
    print; next
  }
  state == 1 {
    if ($0 ~ /^[[:space:]]*\][[:space:]]*,?[[:space:]]*$/) {
      for (i = 1; i <= item_count; i++) {
        line = items[i]
        if (i == item_count && line !~ /,[[:space:]]*$/)
          line = strip_trailing_space(line) ","
        print line
      }
      if (item_count > 0) {
        match(items[1], /^[[:space:]]*/); indent = substr(items[1], 1, RLENGTH)
      } else indent = item_indent
      print indent "\"" value "\""
      print $0
      state = 0; next
    }
    items[++item_count] = $0; next
  }
  END { if (state == 1) exit 3 }
'

# Creates `"key": ["value"]` as the first member of the object `parent`, when
# that object opens on its own line (e.g. a profile with no persist.files).
# shellcheck disable=SC2016 # an awk program, not shell
_JSONC_CREATE_ARRAY_PROGRAM='
  pending {
    separator = ($0 ~ /^[[:space:]]*}/) ? "" : ","
    print indent "\"" key "\": [\"" value "\"]" separator
    pending = 0
  }
  { print }
  $0 ~ "^[[:space:]]*\"" parent "\"[[:space:]]*:" && $0 ~ /\{[[:space:]]*$/ {
    match($0, /^[[:space:]]*/); indent = substr($0, 1, RLENGTH) "  "
    pending = 1
  }
'

# Removes `value` from the array whose key is `key`, one-line or multi-line,
# fixing the commas of what is left. Exits 3 on an array that never closes.
# shellcheck disable=SC2016 # an awk program, not shell
_JSONC_REMOVE_PROGRAM='
  function strip_trailing_space(text) {
    sub(/[[:space:]]+$/, "", text); return text
  }
  BEGIN { state = 0; item_count = 0 }
  state == 0 {
    opening = "^[[:space:]]*\"" key "\"[[:space:]]*:[[:space:]]*\\["
    if (match($0, opening)) {
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
        print before kept_elements after; next
      }
      print; state = 1; item_count = 0; next
    }
    print; next
  }
  state == 1 {
    if ($0 ~ /^[[:space:]]*\][[:space:]]*,?[[:space:]]*$/) {
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
      state = 0; item_count = 0; next
    }
    items[++item_count] = $0; next
  }
  END { if (state == 1) exit 3 }
'

# jsonc_append_to_array FILE SELECTOR VALUE
#   Appends VALUE to the array at SELECTOR (e.g. ".persist.files"),
#   preserving comments and formatting. No-op if VALUE already present.
#   Selector's last key is the array name; one such key per file is assumed.
jsonc_append_to_array() {
  local file="$1" selector="$2" value="$3"
  local key="${selector##*.}"
  if grep -qF "\"$value\"" "$file"; then
    return 0
  fi
  local temporary_file; temporary_file="$(mktemp)"
  awk -v key="$key" -v value="$value" "$_JSONC_APPEND_PROGRAM" "$file" \
    > "$temporary_file" || : > "$temporary_file"
  # No such array: create it as the first member of its parent object.
  local parent="${selector%.*}"; parent="${parent##*.}"
  if [[ -s "$temporary_file" && -n "$parent" ]] \
     && ! grep -qF "\"$value\"" "$temporary_file"; then
    awk -v parent="$parent" -v key="$key" -v value="$value" \
      "$_JSONC_CREATE_ARRAY_PROGRAM" "$file" > "$temporary_file"
  fi
  grep -qF "\"$value\"" "$temporary_file" || {
    rm -f "$temporary_file"
    echo "jsonc: cannot append to ${selector} in ${file}" \
         "(missing or unsupported array); file left unchanged" >&2
    return 1
  }
  mv "$temporary_file" "$file"
}

# jsonc_remove_from_array FILE SELECTOR VALUE
#   Removes VALUE from the array at SELECTOR. No-op if absent.
jsonc_remove_from_array() {
  local file="$1" selector="$2" value="$3"
  local key="${selector##*.}"
  if ! grep -qF "\"$value\"" "$file"; then
    return 0
  fi
  local temporary_file; temporary_file="$(mktemp)"
  awk -v key="$key" -v value="$value" "$_JSONC_REMOVE_PROGRAM" "$file" \
    > "$temporary_file" || {
    rm -f "$temporary_file"
    echo "jsonc: cannot remove from ${selector} in ${file}" \
         "(unterminated array); file left unchanged" >&2
    return 1
  }
  mv "$temporary_file" "$file"
}
