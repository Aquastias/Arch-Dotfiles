#!/usr/bin/env bash
# =============================================================================
# lib/jsonc.sh — JSONC parsing primitives
# =============================================================================
# Pure — no dependencies, no error() calls.
# Sourced by lib/common.sh and lib/config/layers.sh.
# =============================================================================

# jsonc_strip FILE → strips // line-comments, emits plain JSON on stdout.
jsonc_strip() {
  sed \
    -e 's|[[:space:]]*//$||' \
    -e 's|[[:space:]]//[^"]*$||' \
    -e '/^[[:space:]]*\/\//d' \
    "$1" 2>/dev/null
}

# jsonc FILE → alias for jsonc_strip; retained for callers predating the rename.
jsonc() { jsonc_strip "$1"; }

# jsonc_read FILE PATH → raw jq read; jq null for missing fields.
jsonc_read() { jsonc_strip "$1" | jq -r "$2"; }

# jsonc_read_opt FILE PATH → empty string if field is missing or null.
jsonc_read_opt() { jsonc_strip "$1" | jq -r "$2 // empty"; }

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
  local tmp; tmp="$(mktemp)"
  awk -v key="$key" -v val="$value" '
    function rstrip(s) { sub(/[[:space:]]+$/, "", s); return s }
    BEGIN { state = 0; n = 0 }
    state == 0 {
      pat = "^([[:space:]]*)\"" key "\"[[:space:]]*:[[:space:]]*\\["
      if (match($0, pat)) {
        rs = RSTART; rl = RLENGTH
        match($0, /^[[:space:]]*/); base = substr($0, 1, RLENGTH)
        iind = base "  "
        tail = substr($0, rs + rl)
        sub(/^[[:space:]]+/, "", tail)
        if (tail ~ /^\][[:space:]]*,?[[:space:]]*$/) {
          tc = (tail ~ /\][[:space:]]*,/) ? "," : ""
          pre = substr($0, 1, rs + rl - 1)
          print pre
          print iind "\"" val "\""
          print base "]" tc
          next
        }
        # One-line non-empty array: insert before its closing bracket.
        if (match($0, /\][^\]]*$/)) {
          head = rstrip(substr($0, 1, RSTART - 1))
          print head ", \"" val "\"" substr($0, RSTART)
          next
        }
        print; state = 1; n = 0; next
      }
      print; next
    }
    state == 1 {
      if ($0 ~ /^[[:space:]]*\][[:space:]]*,?[[:space:]]*$/) {
        for (i = 1; i <= n; i++) {
          line = items[i]
          if (i == n && line !~ /,[[:space:]]*$/) line = rstrip(line) ","
          print line
        }
        if (n > 0) {
          match(items[1], /^[[:space:]]*/); ii = substr(items[1], 1, RLENGTH)
        } else ii = iind
        print ii "\"" val "\""
        print $0
        state = 0; next
      }
      items[++n] = $0; next
    }
    # An array never closed on its own line would drop every buffered line.
    END { if (state == 1) exit 3 }
  ' "$file" > "$tmp" || : > "$tmp"
  # No such array: create it as the first member of its parent object, when
  # that object opens on its own line (e.g. a profile with no persist.files).
  local parent="${selector%.*}"; parent="${parent##*.}"
  if [[ -s "$tmp" && -n "$parent" ]] && ! grep -qF "\"$value\"" "$tmp"; then
    awk -v parent="$parent" -v key="$key" -v val="$value" '
      pend {
        c = ($0 ~ /^[[:space:]]*}/) ? "" : ","
        print ind "\"" key "\": [\"" val "\"]" c
        pend = 0
      }
      { print }
      $0 ~ "^[[:space:]]*\"" parent "\"[[:space:]]*:" \
        && $0 ~ /\{[[:space:]]*$/ {
        match($0, /^[[:space:]]*/); ind = substr($0, 1, RLENGTH) "  "
        pend = 1
      }
    ' "$file" > "$tmp"
  fi
  grep -qF "\"$value\"" "$tmp" || {
    rm -f "$tmp"
    echo "jsonc: cannot append to ${selector} in ${file}" \
         "(missing or unsupported array); file left unchanged" >&2
    return 1
  }
  mv "$tmp" "$file"
}

# jsonc_remove_from_array FILE SELECTOR VALUE
#   Removes VALUE from the array at SELECTOR. No-op if absent.
jsonc_remove_from_array() {
  local file="$1" selector="$2" value="$3"
  local key="${selector##*.}"
  if ! grep -qF "\"$value\"" "$file"; then
    return 0
  fi
  local tmp; tmp="$(mktemp)"
  awk -v key="$key" -v val="$value" '
    function rstrip(s) { sub(/[[:space:]]+$/, "", s); return s }
    BEGIN { state = 0; n = 0 }
    state == 0 {
      pat = "^[[:space:]]*\"" key "\"[[:space:]]*:[[:space:]]*\\["
      if (match($0, pat)) {
        pre = substr($0, 1, RSTART + RLENGTH - 1)
        tail = substr($0, RSTART + RLENGTH)
        # One-line array: rebuild its element list without VAL.
        if (match(tail, /\][^\]]*$/)) {
          post = substr(tail, RSTART)
          k = split(substr(tail, 1, RSTART - 1), parts, ",")
          out = ""
          for (i = 1; i <= k; i++) {
            p = parts[i]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", p)
            if (p == "" || p == "\"" val "\"") continue
            out = out (out == "" ? "" : ", ") p
          }
          print pre out post; next
        }
        print; state = 1; n = 0; next
      }
      print; next
    }
    state == 1 {
      if ($0 ~ /^[[:space:]]*\][[:space:]]*,?[[:space:]]*$/) {
        m = 0
        for (i = 1; i <= n; i++) {
          if (items[i] ~ "\"" val "\"") continue
          kept[++m] = items[i]
        }
        for (i = 1; i <= m; i++) {
          line = kept[i]
          if (i == m) sub(/,[[:space:]]*$/, "", line)
          else if (line !~ /,[[:space:]]*$/) line = rstrip(line) ","
          print line
        }
        print $0
        state = 0; n = 0; next
      }
      items[++n] = $0; next
    }
    END { if (state == 1) exit 3 }
  ' "$file" > "$tmp" || {
    rm -f "$tmp"
    echo "jsonc: cannot remove from ${selector} in ${file}" \
         "(unterminated array); file left unchanged" >&2
    return 1
  }
  mv "$tmp" "$file"
}
