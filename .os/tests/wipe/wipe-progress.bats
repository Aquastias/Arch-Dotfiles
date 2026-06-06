#!/usr/bin/env bats
# Unit tests for lib/wipe/progress.sh — the Progress Renderer.
# Pure: bytes + size → percent/bar/rate/ETA. No terminal or real disk involved.

setup() {
  # shellcheck source=../../lib/wipe/progress.sh
  source "$BATS_TEST_DIRNAME/../../lib/wipe/progress.sh"
}

@test "progress_pct: bytes/size as an integer percent" {
  run progress_pct 50 100
  [ "$status" -eq 0 ]
  [ "$output" = "50" ]
}

@test "progress_pct: clamps at 100 when bytes exceed size" {
  run progress_pct 150 100
  [ "$output" = "100" ]
}

@test "progress_pct: size of 0 yields 0 (no divide-by-zero)" {
  run progress_pct 5 0
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "progress_bar: fills proportionally to width" {
  run progress_bar 50 100 10
  [ "$output" = "[#####-----]" ]
}

@test "progress_bar: clamps to a full bar past 100%" {
  run progress_bar 200 100 10
  [ "$output" = "[##########]" ]
}

@test "progress_parse_bytes: extracts the byte count from a dd sample" {
  run progress_parse_bytes "524288000 bytes (524 MB, 500 MiB) copied, 2 s, 262 MB/s"
  [ "$output" = "524288000" ]
}

@test "progress_parse_bytes: takes the latest sample from a \\r stream" {
  local stream=$'100 bytes (100 B) copied, 0 s\r524288000 bytes (524 MB) copied, 2 s, 262 MB/s'
  run progress_parse_bytes "$stream"
  [ "$output" = "524288000" ]
}

@test "progress_parse_bytes: empty when there is no sample yet" {
  run progress_parse_bytes ""
  [ "$output" = "" ]
  run progress_parse_bytes "Zero-filling /dev/sda ..."
  [ "$output" = "" ]
}

@test "progress_rate: bytes over seconds as an SI rate" {
  run progress_rate 82000000 1
  [ "$output" = "82 MB/s" ]
}

@test "progress_eta: remaining time as mm:ss" {
  run progress_eta 50 100 10   # 5 B/s, 50 B left → 10 s
  [ "$output" = "00:10" ]
}

@test "progress_eta: unknown (--:--) before any bytes are written" {
  run progress_eta 0 100 5
  [ "$output" = "--:--" ]
}

@test "progress_line: composes label, bar, percent, rate and ETA" {
  run progress_line sda 50 100 10 10
  [ "$status" -eq 0 ]
  [[ "$output" == sda* ]]
  [[ "$output" == *"[#####-----]"* ]]
  [[ "$output" == *"50%"* ]]
  [[ "$output" == *"5 B/s"* ]]
  [[ "$output" == *"00:10"* ]]
}
