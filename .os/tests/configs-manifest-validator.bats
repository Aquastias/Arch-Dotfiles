#!/usr/bin/env bats
# Tests for lib/configs-generator.sh — Manifest Validator (happy path).

setup() {
  TEST_DIR="$(mktemp -d)"
  # shellcheck source=../lib/configs-generator.sh
  source "$BATS_TEST_DIRNAME/../lib/configs-generator.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "validator: parses JSONC with files[{src,dst}] and returns 0" {
  mkdir -p "$TEST_DIR/configs"
  printf 'placeholder\n' > "$TEST_DIR/configs/greeting"
  cat > "$TEST_DIR/configs/manifest.jsonc" <<'JSONC'
{
  // hello fixture
  "files": [
    { "src": "greeting", "dst": "~/.config/hello/greeting" }
  ]
}
JSONC

  run cg_validate_manifest "$TEST_DIR/configs/manifest.jsonc"
  [ "$status" -eq 0 ]
}
