#!/usr/bin/env bats
# Tests for .installer/lib/config/printing.sh — the Printing Service resolver (ADR
# 0079): a pure helper turning options.printing.enabled into the toggle-derived
# System Programs (cups when on, nothing when off), the injector that folds cups
# into an Effective Config's host_programs, and the picker-filter owned set.
#
# Behaviour under test (external only — the decision the helper produces), never
# internal structure. Prior art: tests/config/post-install.bats.

setup() {
  error() { echo "[error] $*" >&2; return 1; }
  export -f error
  # shellcheck source=../../lib/config/printing.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/printing.sh"
}

# ── printing_enabled: default on; explicit false off ────────────────────────

@test "printing_enabled: absent toggle defaults on" {
  [ "$(printing_enabled '{}')" = "true" ]
  [ "$(printing_enabled '{"options":{}}')" = "true" ]
}

@test "printing_enabled: explicit true is on" {
  [ "$(printing_enabled '{"options":{"printing":{"enabled":true}}}')" = "true" ]
}

@test "printing_enabled: explicit false is off" {
  local off='{"options":{"printing":{"enabled":false}}}'
  [ "$(printing_enabled "$off")" = "false" ]
}

# ── printing_programs: cups when on, nothing when off ───────────────────────

@test "printing_programs: on yields cups" {
  run printing_programs '{"options":{"printing":{"enabled":true}}}'
  [ "$status" -eq 0 ]
  [ "$output" = "cups" ]
}

@test "printing_programs: absent toggle (default on) yields cups" {
  run printing_programs '{}'
  [ "$output" = "cups" ]
}

@test "printing_programs: off yields nothing" {
  run printing_programs '{"options":{"printing":{"enabled":false}}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── printing_inject: folds cups into host_programs when on ────────────────

@test "printing_inject: on adds cups to an empty host_programs" {
  run printing_inject '{"options":{"printing":{"enabled":true}}}'
  echo "$output" | jq -e '.host_programs == ["cups"]'
}

@test "printing_inject: on preserves existing programs and appends cups" {
  run printing_inject '{"host_programs":["grub"],
                        "options":{"printing":{"enabled":true}}}'
  echo "$output" | jq -e '.host_programs == ["grub","cups"]'
}

@test "printing_inject: idempotent when cups already present" {
  run printing_inject '{"host_programs":["cups"],
                        "options":{"printing":{"enabled":true}}}'
  echo "$output" | jq -e '.host_programs == ["cups"]'
}

@test "printing_inject: default-on (absent toggle) still injects cups" {
  run printing_inject '{"host_programs":["grub"]}'
  echo "$output" | jq -e '.host_programs == ["grub","cups"]'
}

@test "printing_inject: off is a no-op (no cups, existing kept)" {
  run printing_inject '{"host_programs":["grub"],
                        "options":{"printing":{"enabled":false}}}'
  echo "$output" | jq -e '.host_programs == ["grub"]'
}

@test "printing_inject: off leaves a config with no host_programs untouched" {
  run printing_inject '{"options":{"printing":{"enabled":false}}}'
  echo "$output" | jq -e 'has("host_programs") | not'
}

# ── printing_owned_programs: the picker-filter set ──────────────────────────

@test "printing_owned_programs: lists cups" {
  run printing_owned_programs
  [ "$output" = "cups" ]
}
