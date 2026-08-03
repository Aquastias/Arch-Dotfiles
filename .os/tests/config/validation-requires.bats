#!/usr/bin/env bats
# Tests for the program-dependency ordering check in lib/config/validation.sh
# (ADR 0065). A program's declared `requires: [...]` must be installed before
# it — either a host system program (installed before all user programs) or an
# earlier entry in the same user's list. Enforced at validate_install_context
# time, before any install side effect.

setup() {
  TEST_DIR="$(mktemp -d)"
  export OS_DIR="$TEST_DIR"
  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=../../lib/config/layers.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/layers.sh"
  # shellcheck source=../../lib/config/validation.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/validation.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# Write a program fixture; $4 (optional) is a JSON array for `requires`.
write_program() {
  local cat="$1" name="$2" system="$3" requires="${4:-}"
  mkdir -p "$TEST_DIR/programs/$cat/$name"
  if [[ -n "$requires" ]]; then
    printf '{"name":"%s","system":%s,"requires":%s}\n' \
      "$name" "$system" "$requires" \
      > "$TEST_DIR/programs/$cat/$name/config.jsonc"
  else
    printf '{"name":"%s","system":%s}\n' "$name" "$system" \
      > "$TEST_DIR/programs/$cat/$name/config.jsonc"
  fi
  printf '#!/bin/sh\n' > "$TEST_DIR/programs/$cat/$name/install.sh"
}

@test "requires: reads the declared dependency list" {
  write_program privacy searxng false '["podman"]'
  run _validation_program_requires searxng
  [ "$status" -eq 0 ]
  [ "$output" = "podman" ]
}

@test "requires: a program without the field yields nothing" {
  write_program virtualization podman false
  run _validation_program_requires podman
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "order: dependency declared earlier in the same user passes" {
  write_program virtualization podman false
  write_program privacy searxng false '["podman"]'
  run _validation_check_requires_order alice '[]' '["podman","searxng"]'
  [ "$status" -eq 0 ]
}

@test "order: dependency listed after the dependent fails" {
  write_program virtualization podman false
  write_program privacy searxng false '["podman"]'
  run _validation_check_requires_order alice '[]' '["searxng","podman"]'
  [ "$status" -ne 0 ]
  [[ "$output" == *searxng* && "$output" == *podman* ]]
}

@test "order: a missing dependency fails with a declare-it message" {
  write_program privacy searxng false '["podman"]'
  run _validation_check_requires_order alice '[]' '["searxng"]'
  [ "$status" -ne 0 ]
  [[ "$output" == *"not"* && "$output" == *podman* ]]
}

@test "order: a dependency met by a host system program passes" {
  write_program virtualization podman true
  write_program privacy searxng false '["podman"]'
  run _validation_check_requires_order alice '["podman"]' '["searxng"]'
  [ "$status" -eq 0 ]
}

@test "order: no requires anywhere passes trivially" {
  write_program virtualization docker false
  write_program privacy searxng false
  run _validation_check_requires_order alice '[]' '["docker","searxng"]'
  [ "$status" -eq 0 ]
}
