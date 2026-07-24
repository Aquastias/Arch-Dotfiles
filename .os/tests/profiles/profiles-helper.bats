#!/usr/bin/env bats
# Tests for the AUR-helper foundations in lib/profiles/runner.sh (ADR 0052):
#   _retry                  — generic retry-with-backoff wrapper
#   _profiles_detect_helper — resolve paru|yay from PATH ($AUR_HELPER value)
#
# Both are pure: no paru, no chroot. _retry's sleep is shadowed by a test
# function that records the backoff sequence, so tests run instantly.

setup() {
  TEST_DIR="$(mktemp -d)"

  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=../../lib/config/categorized-list.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/categorized-list.sh"
  # shellcheck source=../../lib/profiles/runner.sh
  source "$BATS_TEST_DIRNAME/../../lib/profiles/runner.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# ── _retry ──────────────────────────────────────────────────────────────────

# A fake command that fails its first N invocations then succeeds. State lives
# in a file so it survives across the separate process the command runs in.
_flaky() {
  local fail_n="$1" counter="$2"
  local n; n="$(cat "$counter")"; n=$((n + 1)); printf '%s' "$n" > "$counter"
  (( n > fail_n ))
}

# Records each sleep duration into SLEEPS_FILE, never actually sleeps.
_record_sleep() { printf '%s\n' "$1" >> "$SLEEPS_FILE"; }

@test "_retry: command that succeeds first try runs once, never sleeps" {
  SLEEPS_FILE="$TEST_DIR/sleeps"; : > "$SLEEPS_FILE"
  sleep() { _record_sleep "$@"; }

  run _retry 3 "3,10" -- true
  [ "$status" -eq 0 ]
  [ ! -s "$SLEEPS_FILE" ]
}

@test "_retry: fails twice then succeeds on the third try, sleeping 3 then 10" {
  SLEEPS_FILE="$TEST_DIR/sleeps"; : > "$SLEEPS_FILE"
  sleep() { _record_sleep "$@"; }
  printf '0' > "$TEST_DIR/ctr"

  run _retry 3 "3,10" -- _flaky 2 "$TEST_DIR/ctr"
  [ "$status" -eq 0 ]
  [ "$(cat "$SLEEPS_FILE")" = "$(printf '3\n10')" ]
}

@test "_retry: exhausts all tries and returns the command's failure status" {
  SLEEPS_FILE="$TEST_DIR/sleeps"; : > "$SLEEPS_FILE"
  sleep() { _record_sleep "$@"; }

  # `false` always fails; 3 tries → 2 sleeps (3,10), final status non-zero.
  run _retry 3 "3,10" -- false
  [ "$status" -ne 0 ]
  [ "$(cat "$SLEEPS_FILE")" = "$(printf '3\n10')" ]
}

@test "_retry: missing backoff values default to 0" {
  SLEEPS_FILE="$TEST_DIR/sleeps"; : > "$SLEEPS_FILE"
  sleep() { _record_sleep "$@"; }

  # 4 tries but only one backoff value: gaps 2,0,0.
  run _retry 4 "2" -- false
  [ "$status" -ne 0 ]
  [ "$(cat "$SLEEPS_FILE")" = "$(printf '2\n0\n0')" ]
}

# ── _profiles_detect_helper ─────────────────────────────────────────────────

# Put fake helper executables on an isolated PATH.
_stub_helpers() {
  local bin="$TEST_DIR/bin"; mkdir -p "$bin"
  local h
  for h in "$@"; do printf '#!/bin/sh\n' > "$bin/$h"; chmod +x "$bin/$h"; done
  PATH="$bin"
}

@test "_profiles_detect_helper: only paru → paru" {
  local saved="$PATH"; _stub_helpers paru
  run _profiles_detect_helper
  PATH="$saved"
  [ "$status" -eq 0 ]
  [ "$output" = "paru" ]
}

@test "_profiles_detect_helper: only yay → yay" {
  local saved="$PATH"; _stub_helpers yay
  run _profiles_detect_helper
  PATH="$saved"
  [ "$status" -eq 0 ]
  [ "$output" = "yay" ]
}

@test "_profiles_detect_helper: both present → paru (preferred)" {
  local saved="$PATH"; _stub_helpers paru yay
  run _profiles_detect_helper
  PATH="$saved"
  [ "$status" -eq 0 ]
  [ "$output" = "paru" ]
}

@test "_profiles_detect_helper: neither present → non-zero, no output" {
  local saved="$PATH"; _stub_helpers   # empty bin dir
  run _profiles_detect_helper
  PATH="$saved"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}
