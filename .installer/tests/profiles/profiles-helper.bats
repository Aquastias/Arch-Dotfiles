#!/usr/bin/env bats
# Tests for the AUR-helper foundations (ADR 0052), runner.sh + common.sh:
#   _retry                  — generic retry-with-backoff wrapper
#   aur_helper_detect — resolve paru|yay from PATH ($AUR_HELPER value)
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


@test "_retry: marks attempts and retried failures on stderr, not stdout" {
  sleep() { :; }
  printf '0' > "$TEST_DIR/ctr"
  _retry 3 "3,10" -- _flaky 1 "$TEST_DIR/ctr" \
    > "$TEST_DIR/out" 2> "$TEST_DIR/err"
  [ ! -s "$TEST_DIR/out" ]
  grep -qx '\[ATTEMPT\] 1/3 _flaky' "$TEST_DIR/err"
  grep -q '^\[RETRY\] attempt 1/3 of _flaky returned 1' "$TEST_DIR/err"
  grep -qx '\[ATTEMPT\] 2/3 _flaky' "$TEST_DIR/err"
  [ "$(grep -c '^\[RETRY\]' "$TEST_DIR/err")" -eq 1 ]
}

# ── aur_helper_detect ─────────────────────────────────────────────────

# Put fake helper executables on an isolated PATH.
_stub_helpers() {
  local bin="$TEST_DIR/bin"; mkdir -p "$bin"
  local h
  for h in "$@"; do printf '#!/bin/sh\n' > "$bin/$h"; chmod +x "$bin/$h"; done
  PATH="$bin"
}

@test "aur_helper_detect: only paru → paru" {
  local saved="$PATH"; _stub_helpers paru
  run aur_helper_detect
  PATH="$saved"
  [ "$status" -eq 0 ]
  [ "$output" = "paru" ]
}

@test "aur_helper_detect: only yay → yay" {
  local saved="$PATH"; _stub_helpers yay
  run aur_helper_detect
  PATH="$saved"
  [ "$status" -eq 0 ]
  [ "$output" = "yay" ]
}

@test "aur_helper_detect: both present → paru (preferred)" {
  local saved="$PATH"; _stub_helpers paru yay
  run aur_helper_detect
  PATH="$saved"
  [ "$status" -eq 0 ]
  [ "$output" = "paru" ]
}

@test "aur_helper_detect: neither present → non-zero, no output" {
  local saved="$PATH"; _stub_helpers   # empty bin dir
  run aur_helper_detect
  PATH="$saved"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

# ── AUR Vetting helper policy (ADR 0143) ────────────────────────────────────

@test "aur_helper_vets_aur: only paru carries the vetting hook" {
  aur_helper_vets_aur paru
  ! aur_helper_vets_aur yay
}

@test "aur_helper_repo_command: yay is repo-only, paru unchanged" {
  [ "$(aur_helper_repo_command yay)" = "yay --repo" ]
  [ "$(aur_helper_repo_command paru)" = "paru" ]
}
