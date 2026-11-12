#!/usr/bin/env bash
# lib/shell/files.sh — line edits of root-owned config files (run as root
# through sudo); each file keeps its owner and mode (ADR 0167: these replace
# sed's address forms, `sed -i '/re/d'` and `sed -i '/re/i …'`).

# remove_lines_matching <file> <extended-regex> — delete every line of <file>
# that matches.
# Root reads and writes <file>; the temp file is the caller's own.
# shellcheck disable=SC2024
remove_lines_matching() {
  local file="$1" pattern="$2" kept
  kept="$(mktemp)"
  # Every line that does not match (grep fails when none is left: fine).
  sudo grep -vE "$pattern" "$file" > "$kept" || true
  sudo tee "$file" < "$kept" >/dev/null
  rm -f "$kept"
}

# insert_before_matching <file> <extended-regex> <text> — put <text> (one or
# more lines) right before every line of <file> that matches. (The `|| -n`
# keeps a last line that has no newline.)
# Root reads and writes <file>; the temp file is the caller's own.
# shellcheck disable=SC2024
insert_before_matching() {
  local file="$1" pattern="$2" text="$3" edited line
  edited="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if printf '%s\n' "$line" | grep -qE "$pattern"; then
      printf '%s\n' "$text"
    fi
    printf '%s\n' "$line"
  done < <(sudo cat "$file") > "$edited"
  sudo tee "$file" < "$edited" >/dev/null
  rm -f "$edited"
}
