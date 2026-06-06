#!/usr/bin/env bats
# Unit tests for lib/wipe/method.sh — the Wipe-Method Selector.
# Pure rota→method routing; no real device is touched.

setup() {
  # shellcheck source=../../lib/wipe/method.sh
  source "$BATS_TEST_DIRNAME/../../lib/wipe/method.sh"
}

@test "wipe_method: non-rotational (SSD/NVMe) selects blkdiscard" {
  run wipe_method 0
  [ "$status" -eq 0 ]
  [ "$output" = "blkdiscard" ]
}

@test "wipe_method: rotational (HDD) selects dd" {
  run wipe_method 1
  [ "$status" -eq 0 ]
  [ "$output" = "dd" ]
}

@test "wipe_method: unknown rota falls back to the safe dd zero-pass" {
  run wipe_method ""
  [ "$output" = "dd" ]
  run wipe_method "?"
  [ "$output" = "dd" ]
}

# Guard the make-blank contract: the selector only ever routes to a non-forensic
# method, never shred/secure-erase, for any rota value.
@test "wipe_method: never selects shred for any rota value" {
  local rota
  for rota in 0 1 "" "?" 2; do
    run wipe_method "$rota"
    [[ "$output" == "blkdiscard" || "$output" == "dd" ]]
    [[ "$output" != *shred* ]]
  done
}
