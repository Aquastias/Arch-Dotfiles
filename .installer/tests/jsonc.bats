#!/usr/bin/env bats
# Tests for .os/lib/jsonc.sh — JSONC comment stripping and field reading.

setup() {
  TEST_DIR="$(mktemp -d)"
  # shellcheck source=../lib/jsonc.sh
  source "$BATS_TEST_DIRNAME/../lib/jsonc.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

write_file() {
  local path="$1" content="$2"
  printf '%s\n' "$content" > "$path"
}

# ── jsonc_strip ───────────────────────────────────────────────────────────────

@test "jsonc_strip: plain JSON is emitted unchanged" {
  write_file "$TEST_DIR/f.json" '{"key": "value"}'
  run jsonc_strip "$TEST_DIR/f.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"key": "value"'* ]]
}

@test "jsonc_strip: standalone comment lines are removed" {
  write_file "$TEST_DIR/f.jsonc" '{
// this whole line is a comment
"key": "value"
}'
  run jsonc_strip "$TEST_DIR/f.jsonc"
  [ "$status" -eq 0 ]
  ! [[ "$output" == *"this whole line"* ]]
  [[ "$output" == *'"key": "value"'* ]]
}

@test "jsonc_strip: trailing // comments are removed" {
  write_file "$TEST_DIR/f.jsonc" '{"key": "value" // trailing comment}'
  run jsonc_strip "$TEST_DIR/f.jsonc"
  [ "$status" -eq 0 ]
  ! [[ "$output" == *"trailing comment"* ]]
  [[ "$output" == *'"key": "value"'* ]]
}

@test "jsonc_strip: result is valid JSON parseable by jq" {
  write_file "$TEST_DIR/f.jsonc" '{
// comment
"a": 1, // inline
"b": "two"
}'
  run bash -c "source '$BATS_TEST_DIRNAME/../lib/jsonc.sh' \
    && jsonc_strip '$TEST_DIR/f.jsonc' | jq -r '.b'"
  [ "$status" -eq 0 ]
  [ "$output" = "two" ]
}

# ── jsonc_read_opt ────────────────────────────────────────────────────────────

@test "jsonc_read_opt: returns value for a present field" {
  write_file "$TEST_DIR/f.json" '{"options": {"kernel": "lts"}}'
  run jsonc_read_opt "$TEST_DIR/f.json" '.options.kernel'
  [ "$status" -eq 0 ]
  [ "$output" = "lts" ]
}

@test "jsonc_read_opt: returns empty string for a missing field" {
  write_file "$TEST_DIR/f.json" '{}'
  run jsonc_read_opt "$TEST_DIR/f.json" '.options.kernel'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "jsonc_read_opt: returns empty string for an explicit null field" {
  write_file "$TEST_DIR/f.json" '{"options": {"kernel": null}}'
  run jsonc_read_opt "$TEST_DIR/f.json" '.options.kernel'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── jsonc_read ────────────────────────────────────────────────────────────────

@test "jsonc_read: returns literal null string for a missing field" {
  write_file "$TEST_DIR/f.json" '{}'
  run jsonc_read "$TEST_DIR/f.json" '.missing'
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

@test "jsonc_read: returns the value for a present field" {
  write_file "$TEST_DIR/f.json" '{"disk": "/dev/sda"}'
  run jsonc_read "$TEST_DIR/f.json" '.disk'
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sda" ]
}

# ── jsonc_append_to_array ─────────────────────────────────────────────────────

@test "jsonc_append_to_array: appends to empty array" {
  local f="$TEST_DIR/c.jsonc"
  write_file "$f" '{
  "persist": {
    "files": []
  }
}'
  jsonc_append_to_array "$f" '.persist.files' '/etc/foo'
  grep -qE '"/etc/foo"' "$f"
}

@test "jsonc_append_to_array: appends to non-empty array" {
  local f="$TEST_DIR/c.jsonc"
  write_file "$f" '{
  "persist": {
    "files": [
      "/etc/bar"
    ]
  }
}'
  jsonc_append_to_array "$f" '.persist.files' '/etc/foo'
  grep -qE '"/etc/bar"' "$f"
  grep -qE '"/etc/foo"' "$f"
}

@test "jsonc_append_to_array: preserves // line comments" {
  local f="$TEST_DIR/c.jsonc"
  write_file "$f" '{
  // top-level comment
  "persist": {
    // inner comment
    "files": []
  }
}'
  jsonc_append_to_array "$f" '.persist.files' '/etc/foo'
  grep -qF '// top-level comment' "$f"
  grep -qF '// inner comment' "$f"
}

@test "jsonc_append_to_array: no-op when value already present" {
  local f="$TEST_DIR/c.jsonc"
  write_file "$f" '{
  "persist": {
    "files": [
      "/etc/foo"
    ]
  }
}'
  jsonc_append_to_array "$f" '.persist.files' '/etc/foo'
  # exactly one occurrence
  local n; n="$(grep -cE '"/etc/foo"' "$f")"
  [ "$n" -eq 1 ]
}

# ── jsonc_remove_from_array ───────────────────────────────────────────────────

@test "jsonc_remove_from_array: removes the value" {
  local f="$TEST_DIR/c.jsonc"
  write_file "$f" '{
  "persist": {
    "files": [
      "/etc/foo",
      "/etc/bar"
    ]
  }
}'
  jsonc_remove_from_array "$f" '.persist.files' '/etc/foo'
  ! grep -qE '"/etc/foo"' "$f"
  grep -qE '"/etc/bar"' "$f"
}

@test "jsonc_remove_from_array: preserves comments" {
  local f="$TEST_DIR/c.jsonc"
  write_file "$f" '{
  // top-level comment
  "persist": {
    "files": [
      "/etc/foo"
    ]
  }
}'
  jsonc_remove_from_array "$f" '.persist.files' '/etc/foo'
  grep -qF '// top-level comment' "$f"
}

@test "jsonc_remove_from_array: no-op when value absent" {
  local f="$TEST_DIR/c.jsonc"
  write_file "$f" '{
  "persist": {
    "files": [
      "/etc/bar"
    ]
  }
}'
  run jsonc_remove_from_array "$f" '.persist.files' '/etc/foo'
  [ "$status" -eq 0 ]
  grep -qE '"/etc/bar"' "$f"
}
