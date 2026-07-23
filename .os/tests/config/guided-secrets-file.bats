#!/usr/bin/env bats
# Tests for .os/lib/guided-secrets-file.sh — the in-menu credential handoff file
# (ticket 03). Pure file mutation + queries: the masked tty prompt is glue and
# not covered here. Shape: { root_password?, users?: { <name>: { password } } }.

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/guided-secrets-file.sh"
  FILE="$(mktemp)"
}
teardown() { rm -f "$FILE"; }

@test "init writes an empty object" {
  guided_secretsfile_init "$FILE"
  [ "$(cat "$FILE")" = "{}" ]
}

@test "set_root records the root password" {
  guided_secretsfile_set_root "$FILE" "s3cret"
  [ "$(jq -r '.root_password' "$FILE")" = "s3cret" ]
}

@test "set_user records a per-user password under users.<name>.password" {
  guided_secretsfile_set_user "$FILE" alex "pw1"
  [ "$(jq -r '.users.alex.password' "$FILE")" = "pw1" ]
}

@test "has_root / has_user reflect what is set" {
  printf '{}\n' > "$FILE"
  ! guided_secretsfile_has_root "$FILE"
  ! guided_secretsfile_has_user "$FILE" alex
  guided_secretsfile_set_root "$FILE" "r"
  guided_secretsfile_set_user "$FILE" alex "a"
  guided_secretsfile_has_root "$FILE"
  guided_secretsfile_has_user "$FILE" alex
  ! guided_secretsfile_has_user "$FILE" guest
}

@test "an empty-string password does not count as set" {
  guided_secretsfile_set_root "$FILE" ""
  ! guided_secretsfile_has_root "$FILE"
}

@test "missing: lists root then each user without a password" {
  printf '{}\n' > "$FILE"
  run guided_secretsfile_missing "$FILE" '["alex","guest"]'
  [ "${lines[0]}" = "root" ]
  [ "${lines[1]}" = "alex" ]
  [ "${lines[2]}" = "guest" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "missing: empty when root + all users have passwords" {
  guided_secretsfile_set_root "$FILE" "r"
  guided_secretsfile_set_user "$FILE" alex "a"
  run guided_secretsfile_missing "$FILE" '["alex"]'
  [ -z "$output" ]
}

@test "missing: with no users, only root is required" {
  guided_secretsfile_set_root "$FILE" "r"
  run guided_secretsfile_missing "$FILE" '[]'
  [ -z "$output" ]
}
