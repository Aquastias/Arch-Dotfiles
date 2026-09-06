#!/usr/bin/env bats
# Tests for the program mutual-exclusion check in lib/config/validation.sh
# (ADR 0115). A program's declared `conflicts: [...]` may not name another
# program that also reaches the machine — a host system program or one of the
# same user's programs. Symmetric: one side declaring is enough. Enforced at
# validate_install_context time, before any install side effect.

setup() {
  TEST_DIR="$(mktemp -d)"
  export INSTALLER_DIR="$TEST_DIR"
  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=../../lib/config/layers.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/layers.sh"
  # shellcheck source=../../lib/config/validation.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/validation.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# Write a program fixture; $4 (optional) is a JSON array for `conflicts`.
write_program() {
  local cat="$1" name="$2" system="$3" conflicts="${4:-}" kind
  [[ "$system" == "true" ]] && kind=host || kind=user
  mkdir -p "$TEST_DIR/programs/$cat/$name"
  if [[ -n "$conflicts" ]]; then
    printf '{"name":"%s","kind":"%s","conflicts":%s}\n' \
      "$name" "$kind" "$conflicts" \
      > "$TEST_DIR/programs/$cat/$name/config.jsonc"
  else
    printf '{"name":"%s","kind":"%s"}\n' "$name" "$kind" \
      > "$TEST_DIR/programs/$cat/$name/config.jsonc"
  fi
  printf '#!/bin/sh\n' > "$TEST_DIR/programs/$cat/$name/install.sh"
}

@test "conflicts: reads the declared conflict list" {
  write_program security ufw false '["firewalld"]'
  run _validation_program_conflicts ufw
  [ "$status" -eq 0 ]
  [ "$output" = "firewalld" ]
}

@test "conflicts: a program without the field yields nothing" {
  write_program security ufw false
  run _validation_program_conflicts ufw
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "conflicts: two rivals in one user's list fail" {
  write_program security ufw false '["firewalld"]'
  write_program security firewalld false
  run _validation_check_conflicts alice '[]' '["ufw","firewalld"]'
  [ "$status" -ne 0 ]
  [[ "$output" == *ufw* && "$output" == *firewalld* ]]
}

@test "conflicts: symmetric — declared on either side is enough" {
  write_program security ufw false
  write_program security firewalld false '["ufw"]'
  run _validation_check_conflicts alice '[]' '["ufw","firewalld"]'
  [ "$status" -ne 0 ]
}

@test "conflicts: a mutual declaration reports the pair once" {
  write_program security ufw false '["firewalld"]'
  write_program security firewalld false '["ufw"]'
  run _validation_check_conflicts alice '[]' '["ufw","firewalld"]'
  [ "$status" -ne 0 ]
  # one violation line, not two
  [ "$(printf '%s\n' "$output" | grep -c conflict)" -eq 1 ]
}

@test "conflicts: rival present as a host program fails" {
  write_program security firewalld true
  write_program security ufw false '["firewalld"]'
  run _validation_check_conflicts alice '["firewalld"]' '["ufw"]'
  [ "$status" -ne 0 ]
}

@test "conflicts: rival not present passes" {
  write_program security ufw false '["firewalld"]'
  write_program security firewalld false
  run _validation_check_conflicts alice '[]' '["ufw"]'
  [ "$status" -eq 0 ]
}

@test "conflicts: none declared anywhere passes trivially" {
  write_program security ufw false
  write_program virtualization docker false
  run _validation_check_conflicts alice '[]' '["ufw","docker"]'
  [ "$status" -eq 0 ]
}
