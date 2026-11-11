#!/usr/bin/env bash
# =============================================================================
# lib/jsonc.sh — JSONC parsing primitives
# =============================================================================
# Pure — no dependencies, no error() calls. The line-oriented edits are awk
# programs in the jsonc-*.awk files next to this one.
# Sourced by lib/common.sh and lib/config/program-registry.sh.
# =============================================================================

# The directory holding this file and its jsonc-*.awk programs.
_JSONC_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# jsonc_strip FILE → strips // line-comments, emits plain JSON on stdout.
jsonc_strip() {
  awk -f "$_JSONC_DIRECTORY/jsonc-strip.awk" "$1" 2>/dev/null
}

# jsonc FILE → alias for jsonc_strip; retained for callers predating the rename.
jsonc() { jsonc_strip "$1"; }

# jsonc_read FILE PATH → raw jq read; jq null for missing fields.
jsonc_read() { jsonc_strip "$1" | jq -r "$2"; }

# jsonc_read_optional FILE PATH → empty string if field is missing or null.
jsonc_read_optional() { jsonc_strip "$1" | jq -r "$2 // empty"; }

# ── Array edits that keep comments and formatting ──────────────────────────

# _jsonc_array_has FILE SELECTOR VALUE — 0 when the array at SELECTOR holds
# VALUE (comments stripped; a missing array or unparsable file is "no").
_jsonc_array_has() {
  # Whether the array at SELECTOR holds VALUE.
  jsonc_strip "$1" \
    | jq -e --arg v "$3" "(${2} // []) | index(\$v) != null" >/dev/null 2>&1
}

# jsonc_append_to_array FILE SELECTOR VALUE
#   Appends VALUE to the array at SELECTOR (e.g. ".persist.files"),
#   preserving comments and formatting. No-op if VALUE is already in that
#   array (only that array: a mention elsewhere, e.g. a comment, does not count).
#   Selector's last key is the array name; one such key per file is assumed.
jsonc_append_to_array() {
  local file="$1" selector="$2" value="$3"
  local -a keys
  # The selector's keys, split at the dots (".persist.files" → "", persist,
  # files): the array's key is the last, its parent object's the one before.
  IFS=. read -ra keys < <(printf '%s\n' "$selector")
  local key="${keys[-1]}" parent=""
  (( ${#keys[@]} >= 2 )) && parent="${keys[-2]}"
  _jsonc_array_has "$file" "$selector" "$value" && return 0
  local temporary_file; temporary_file="$(mktemp)"
  awk -f "$_JSONC_DIRECTORY/jsonc-append.awk" -v key="$key" -v value="$value" \
    "$file" > "$temporary_file" || : > "$temporary_file"
  # No such array: create it as the first member of its parent object.
  if [[ -s "$temporary_file" && -n "$parent" ]] \
     && ! _jsonc_array_has "$temporary_file" "$selector" "$value"; then
    awk -f "$_JSONC_DIRECTORY/jsonc-create-array.awk" \
      -v parent="$parent" -v key="$key" -v value="$value" \
      "$file" > "$temporary_file"
  fi
  _jsonc_array_has "$temporary_file" "$selector" "$value" || {
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
  local -a keys
  # The selector's keys, split at the dots: the array's key is the last.
  IFS=. read -ra keys < <(printf '%s\n' "$selector")
  local key="${keys[-1]}"
  if ! grep -qF "\"$value\"" "$file"; then
    return 0
  fi
  local temporary_file; temporary_file="$(mktemp)"
  awk -f "$_JSONC_DIRECTORY/jsonc-remove.awk" -v key="$key" -v value="$value" \
    "$file" > "$temporary_file" || {
    rm -f "$temporary_file"
    echo "jsonc: cannot remove from ${selector} in ${file}" \
         "(unterminated array); file left unchanged" >&2
    return 1
  }
  mv "$temporary_file" "$file"
}
