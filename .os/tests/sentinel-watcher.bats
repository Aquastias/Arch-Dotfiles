#!/usr/bin/env bats
# Tests for .os/lib/sentinel-watcher.sh — installer-completion sentinel reader.

setup() {
  TEST_DIR="$(mktemp -d)"
  LOG="$TEST_DIR/installer.log"

  # shellcheck source=vm/lib/sentinel-watcher.sh
  source "$BATS_TEST_DIRNAME/vm/lib/sentinel-watcher.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── exit-code parsing ────────────────────────────────────────────────────────

@test "zero exit: returns 0" {
  printf 'preamble line\n===INSTALLER-EXIT-0===\ntrailing line\n' > "$LOG"

  run sentinel_watcher_wait "$LOG" 2
  [ "$status" -eq 0 ]
}

@test "non-zero exit: returns the exact integer (7)" {
  printf '===INSTALLER-EXIT-7===\n' > "$LOG"

  run sentinel_watcher_wait "$LOG" 2
  [ "$status" -eq 7 ]
}

@test "non-zero exit: returns the exact integer (42)" {
  printf 'noise\n===INSTALLER-EXIT-42===\n' > "$LOG"

  run sentinel_watcher_wait "$LOG" 2
  [ "$status" -eq 42 ]
}

# ── timeout ──────────────────────────────────────────────────────────────────

@test "no sentinel within timeout: returns 124" {
  printf 'log without a sentinel\nmore noise\n' > "$LOG"

  run sentinel_watcher_wait "$LOG" 1
  [ "$status" -eq 124 ]
}

# ── late creation ────────────────────────────────────────────────────────────

@test "log file appears mid-window with sentinel: returns parsed code" {
  # File does not exist at call time. Backgrounded helper creates it after a
  # short delay with the sentinel; the watcher should pick it up before its
  # 3-second timeout expires.
  (
    sleep 0.3
    printf '===INSTALLER-EXIT-3===\n' > "$LOG"
  ) &

  run sentinel_watcher_wait "$LOG" 3
  [ "$status" -eq 3 ]

  wait || true
}

# ── grow-after-call ──────────────────────────────────────────────────────────

@test "log file exists but sentinel arrives later: returns parsed code" {
  : > "$LOG"
  (
    sleep 0.3
    printf 'midline\n' >> "$LOG"
    sleep 0.2
    printf '===INSTALLER-EXIT-5===\n' >> "$LOG"
  ) &

  run sentinel_watcher_wait "$LOG" 3
  [ "$status" -eq 5 ]

  wait || true
}

# ── log file is not modified ─────────────────────────────────────────────────

@test "watcher does not modify or delete the log" {
  printf '===INSTALLER-EXIT-0===\n' > "$LOG"
  before="$(sha256sum "$LOG" | awk '{print $1}')"

  sentinel_watcher_wait "$LOG" 2 || true
  [ -f "$LOG" ]
  after="$(sha256sum "$LOG" | awk '{print $1}')"
  [ "$before" = "$after" ]
}

# ── trailing whitespace tolerated ────────────────────────────────────────────

@test "sentinel with trailing whitespace: still returns parsed code" {
  printf '===INSTALLER-EXIT-9===   \n' > "$LOG"

  run sentinel_watcher_wait "$LOG" 2
  [ "$status" -eq 9 ]
}

# ── invalid arguments ────────────────────────────────────────────────────────

@test "non-numeric timeout: returns 2 with a clear message" {
  run sentinel_watcher_wait "$LOG" "soon"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "non-negative integer" ]]
}

@test "empty log path: returns 2 with a clear message" {
  run sentinel_watcher_wait "" 1
  [ "$status" -eq 2 ]
  [[ "$output" =~ "log path is empty" ]]
}

# ── sentinel_watcher_wait_marker (literal substring) ──────────────────────────

@test "marker present on its own line: returns 0" {
  printf 'boot noise\n===FIRSTBOOT-OK===\nmore\n' > "$LOG"

  run sentinel_watcher_wait_marker "$LOG" "===FIRSTBOOT-OK===" 2
  [ "$status" -eq 0 ]
}

@test "marker absent within timeout: returns 124" {
  printf 'no marker here\nmore noise\n' > "$LOG"

  run sentinel_watcher_wait_marker "$LOG" "===FIRSTBOOT-OK===" 1
  [ "$status" -eq 124 ]
}

@test "marker appended after a delay: returns 0 before timeout" {
  : > "$LOG"
  (
    sleep 0.3
    printf '===FIRSTBOOT-OK===\n' >> "$LOG"
  ) &

  run sentinel_watcher_wait_marker "$LOG" "===FIRSTBOOT-OK===" 3
  [ "$status" -eq 0 ]

  wait || true
}

@test "serial CRLF line (trailing carriage return): returns 0" {
  printf '===FIRSTBOOT-OK===\r\n' > "$LOG"

  run sentinel_watcher_wait_marker "$LOG" "===FIRSTBOOT-OK===" 2
  [ "$status" -eq 0 ]
}

@test "empty marker: returns 2 with a clear message" {
  printf 'some content\n' > "$LOG"

  run sentinel_watcher_wait_marker "$LOG" "" 1
  [ "$status" -eq 2 ]
  [[ "$output" =~ "marker is empty" ]]
}

@test "marker: non-numeric timeout returns 2 with a clear message" {
  run sentinel_watcher_wait_marker "$LOG" "===FIRSTBOOT-OK===" "soon"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "non-negative integer" ]]
}
