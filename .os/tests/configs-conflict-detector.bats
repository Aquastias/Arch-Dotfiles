#!/usr/bin/env bats
# Tests for lib/configs-generator.sh — Conflict Detector (happy path).

setup() {
  # shellcheck source=../lib/configs-generator.sh
  source "$BATS_TEST_DIRNAME/../lib/configs-generator.sh"
}

@test "detector: tracer always returns empty array" {
  local plan='[{"src_abs":"/x","dst_in_stow_tree":"/y/.config/hello"}]'

  run cg_detect_conflicts "$plan" "" ""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. == []'
}
