#!/usr/bin/env bash
# =============================================================================
# lib/jsonc.sh — JSONC parsing primitives
# =============================================================================
# Pure — no dependencies, no error() calls.
# Sourced by lib/common.sh and lib/configs.sh.
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
  ' "$file" > "$tmp"
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
      if (match($0, pat)) { print; state = 1; n = 0; next }
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
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}
