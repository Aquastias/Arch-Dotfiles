#!/usr/bin/env bats
# Tests for .os/lib/configs.sh — host/user config loader/merger.

setup() {
  TEST_DIR="$(mktemp -d)"
  export OS_DIR="$TEST_DIR"
  # shellcheck source=../lib/configs.sh
  source "$BATS_TEST_DIRNAME/../lib/configs.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

write_config() {
  local path="$1" content="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
}

# ── core + empty specific ─────────────────────────────────────────────────────

@test "host: core + empty specific returns core fields unchanged" {
  write_config "$TEST_DIR/hosts/core/config.jsonc" \
    '{"users": ["alice"], "system_programs": ["firewalld"]}'
  write_config "$TEST_DIR/hosts/desktop/config.jsonc" '{}'

  run load_host_config desktop
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.users == ["alice"]'
  echo "$output" | jq -e '.system_programs == ["firewalld"]'
}

# ── empty core + specific ─────────────────────────────────────────────────────

@test "host: empty core + specific returns specific fields unchanged" {
  write_config "$TEST_DIR/hosts/core/config.jsonc" '{}'
  write_config "$TEST_DIR/hosts/desktop/config.jsonc" \
    '{"users": ["bob"], "system_programs": ["docker"]}'

  run load_host_config desktop
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.users == ["bob"]'
  echo "$output" | jq -e '.system_programs == ["docker"]'
}

# ── list concatenation with dedupe ────────────────────────────────────────────

@test "host: list fields concatenate with dedupe (order preserved)" {
  write_config "$TEST_DIR/hosts/core/config.jsonc" \
    '{"users": ["alice", "shared"], "system_programs": ["firewalld"]}'
  write_config "$TEST_DIR/hosts/desktop/config.jsonc" \
    '{"users": ["shared", "bob"], "system_programs": ["docker"]}'

  run load_host_config desktop
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.users == ["alice", "shared", "bob"]'
  echo "$output" | jq -e '.system_programs == ["firewalld", "docker"]'
}

# ── scalar override ───────────────────────────────────────────────────────────

@test "user: scalar fields are overridden by specific" {
  write_config "$TEST_DIR/users/core/config.jsonc" \
    '{"shell": "/bin/bash", "sudo": false}'
  write_config "$TEST_DIR/users/alex/config.jsonc" \
    '{"shell": "/bin/zsh", "sudo": true}'

  run load_user_config alex
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.shell == "/bin/zsh"'
  echo "$output" | jq -e '.sudo == true'
}

# ── missing field preservation ────────────────────────────────────────────────

@test "user: field present only in core is preserved" {
  write_config "$TEST_DIR/users/core/config.jsonc" \
    '{"shell": "/bin/zsh", "groups": ["wheel"]}'
  write_config "$TEST_DIR/users/alex/config.jsonc" \
    '{"programs": ["teamspeak3"]}'

  run load_user_config alex
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.shell == "/bin/zsh"'
  echo "$output" | jq -e '.groups == ["wheel"]'
  echo "$output" | jq -e '.programs == ["teamspeak3"]'
}

@test "user: field present only in specific is preserved" {
  write_config "$TEST_DIR/users/core/config.jsonc" \
    '{"shell": "/bin/bash"}'
  write_config "$TEST_DIR/users/alex/config.jsonc" \
    '{"git": {"name": "Alex", "email": "alex@example.com"}}'

  run load_user_config alex
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.shell == "/bin/bash"'
  echo "$output" | jq -e '.git.name == "Alex"'
  echo "$output" | jq -e '.git.email == "alex@example.com"'
}

# ── missing core file is hard error ───────────────────────────────────────────

@test "host: missing core file is a hard error (exit 2)" {
  write_config "$TEST_DIR/hosts/desktop/config.jsonc" '{"users": ["alice"]}'

  run load_host_config desktop
  [ "$status" -eq 2 ]
  [[ "$output" =~ "missing hosts core config" ]]
}

@test "user: missing core file is a hard error (exit 2)" {
  write_config "$TEST_DIR/users/alex/config.jsonc" '{"shell": "/bin/zsh"}'

  run load_user_config alex
  [ "$status" -eq 2 ]
  [[ "$output" =~ "missing users core config" ]]
}

# ── missing specific config is graceful (exit 1, core only) ──────────────────

@test "host: missing specific config returns core with exit 1" {
  write_config "$TEST_DIR/hosts/core/config.jsonc" \
    '{"users": ["alice"], "system_programs": ["firewalld"]}'

  run load_host_config desktop
  [ "$status" -eq 1 ]

  echo "$output" | jq -e '.users == ["alice"]'
  echo "$output" | jq -e '.system_programs == ["firewalld"]'
}

@test "user: missing specific config returns core with exit 1" {
  write_config "$TEST_DIR/users/core/config.jsonc" \
    '{"shell": "/bin/zsh", "groups": ["wheel"]}'

  run load_user_config alex
  [ "$status" -eq 1 ]

  echo "$output" | jq -e '.shell == "/bin/zsh"'
  echo "$output" | jq -e '.groups == ["wheel"]'
}

# ── reserved name ─────────────────────────────────────────────────────────────

@test "host: 'core' as hostname is rejected (exit 3)" {
  write_config "$TEST_DIR/hosts/core/config.jsonc" '{"users": ["alice"]}'

  run load_host_config core
  [ "$status" -eq 3 ]
  [[ "$output" =~ "reserved name" ]]
}

@test "user: 'core' as username is rejected (exit 3)" {
  write_config "$TEST_DIR/users/core/config.jsonc" '{"shell": "/bin/bash"}'

  run load_user_config core
  [ "$status" -eq 3 ]
  [[ "$output" =~ "reserved name" ]]
}

# ── deep object merging (bonus, supports git.name + git.email composition) ────

@test "user: object fields are deep-merged" {
  write_config "$TEST_DIR/users/core/config.jsonc" \
    '{"git": {"name": "Default User"}}'
  write_config "$TEST_DIR/users/alex/config.jsonc" \
    '{"git": {"email": "alex@example.com"}}'

  run load_user_config alex
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.git.name == "Default User"'
  echo "$output" | jq -e '.git.email == "alex@example.com"'
}

# ── JSONC comments are stripped ───────────────────────────────────────────────

@test "host: JSONC // comments are stripped before parsing" {
  write_config "$TEST_DIR/hosts/core/config.jsonc" '{
  // comment on its own line
  "users": ["alice"], // trailing comment
  "system_programs": ["firewalld"]
}'
  write_config "$TEST_DIR/hosts/desktop/config.jsonc" '{}'

  run load_host_config desktop
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.users == ["alice"]'
  echo "$output" | jq -e '.system_programs == ["firewalld"]'
}
