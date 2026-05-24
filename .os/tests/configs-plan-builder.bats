#!/usr/bin/env bats
# Tests for lib/configs-generator.sh — Plan Builder (happy path).

setup() {
  TEST_DIR="$(mktemp -d)"
  # shellcheck source=../lib/configs-generator.sh
  source "$BATS_TEST_DIRNAME/../lib/configs-generator.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "plan: single manifest → entries with src_abs and dst_in_stow_tree" {
  local prog_dir="$TEST_DIR/programs/_fixture/hello/configs"
  mkdir -p "$prog_dir"
  printf 'hi\n' > "$prog_dir/greeting"
  cat > "$prog_dir/manifest.jsonc" <<'JSONC'
{ "files": [ { "src": "greeting",
               "dst": "~/.config/hello/greeting" } ] }
JSONC

  local stow_root="$TEST_DIR/.stow/alex"

  run cg_build_plan "$TEST_DIR/programs" \
                    '{"_fixture/hello":"configs"}' \
                    "$stow_root"
  [ "$status" -eq 0 ]

  echo "$output" | jq -e 'length == 1'
  echo "$output" | jq --arg s "$prog_dir/greeting" \
    -e '.[0].src_abs == $s'
  echo "$output" | jq --arg d "$stow_root/.config/hello/greeting" \
    -e '.[0].dst_in_stow_tree == $d'
}
