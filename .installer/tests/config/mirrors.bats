#!/usr/bin/env bats
# Tests for .os/lib/config/mirrors.sh — the Mirror Service resolver (ADR 0089):
# a pure helper turning the Mirrors & Repositories section into its owned Host
# Program (reflector, state-independent), the injector that folds reflector into
# an Effective Config's host_programs, and the picker-filter owned set.
#
# Behaviour under test (external only — the decision the helper produces), never
# internal structure. Prior art: tests/config/printing.bats.

setup() {
  error() { echo "[error] $*" >&2; return 1; }
  export -f error
  # shellcheck source=../../lib/config/mirrors.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/mirrors.sh"
}

# ── mirrors_programs: always reflector (state-independent) ──────────────────

@test "mirrors_programs: yields reflector on an empty config" {
  run mirrors_programs '{}'
  [ "$status" -eq 0 ]
  [ "$output" = "reflector" ]
}

@test "mirrors_programs: yields reflector regardless of config content" {
  run mirrors_programs '{"options":{"mirror_countries":["Germany"]}}'
  [ "$output" = "reflector" ]
}

# ── mirrors_inject: folds reflector into host_programs ──────────────────────

@test "mirrors_inject: adds reflector to an empty host_programs" {
  run mirrors_inject '{}'
  echo "$output" | jq -e '.host_programs == ["reflector"]'
}

@test "mirrors_inject: preserves existing programs and appends reflector" {
  run mirrors_inject '{"host_programs":["grub"]}'
  echo "$output" | jq -e '.host_programs == ["grub","reflector"]'
}

@test "mirrors_inject: idempotent when reflector already present" {
  run mirrors_inject '{"host_programs":["reflector"]}'
  echo "$output" | jq -e '.host_programs == ["reflector"]'
}

# ── mirrors_owned_programs: the picker-filter set ───────────────────────────

@test "mirrors_owned_programs: lists reflector" {
  run mirrors_owned_programs
  [ "$output" = "reflector" ]
}
