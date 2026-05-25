#!/usr/bin/env bats
# Tests for lib/configs-generator.sh — Plan Builder.

setup() {
  TEST_DIR="$(mktemp -d)"
  # shellcheck source=../lib/configs-generator.sh
  source "$BATS_TEST_DIRNAME/../lib/configs-generator.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "plan: declared program produces one entry per manifest file" {
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
                    "$stow_root" \
                    '["hello"]'
  [ "$status" -eq 0 ]

  echo "$output" | jq -e 'length == 1'
  echo "$output" | jq --arg s "$prog_dir/greeting" \
    -e '.[0].src_abs == $s'
  echo "$output" | jq --arg d "$stow_root/.config/hello/greeting" \
    -e '.[0].dst_in_stow_tree == $d'
}

@test "plan: undeclared program with configs/ is dropped" {
  local hello="$TEST_DIR/programs/_fixture/hello/configs"
  local ghost="$TEST_DIR/programs/_fixture/ghost/configs"
  mkdir -p "$hello" "$ghost"
  printf 'hi\n' > "$hello/greeting"
  printf 'boo\n' > "$ghost/scare"
  cat > "$hello/manifest.jsonc" <<'JSONC'
{ "files": [ { "src": "greeting", "dst": "~/.config/hello/greeting" } ] }
JSONC
  cat > "$ghost/manifest.jsonc" <<'JSONC'
{ "files": [ { "src": "scare", "dst": "~/.config/ghost/scare" } ] }
JSONC

  local stow_root="$TEST_DIR/.stow/alex"
  run cg_build_plan "$TEST_DIR/programs" \
    '{"_fixture/hello":"configs","_fixture/ghost":"configs"}' \
    "$stow_root" \
    '["hello"]'
  [ "$status" -eq 0 ]

  echo "$output" | jq -e 'length == 1'
  echo "$output" | jq --arg d "$stow_root/.config/hello/greeting" \
    -e '.[0].dst_in_stow_tree == $d'
  echo "$output" | jq -e '[.[].dst_in_stow_tree] | map(test("ghost")) | any | not'
}

@test "plan: multiple declared programs combine, sorted by dst" {
  local zed="$TEST_DIR/programs/_fixture/zed/configs"
  local atom="$TEST_DIR/programs/_fixture/atom/configs"
  mkdir -p "$zed" "$atom"
  printf 'z\n' > "$zed/zfile"
  printf 'a\n' > "$atom/afile"
  cat > "$zed/manifest.jsonc" <<'JSONC'
{ "files": [ { "src": "zfile", "dst": "~/.config/zed/zfile" } ] }
JSONC
  cat > "$atom/manifest.jsonc" <<'JSONC'
{ "files": [ { "src": "afile", "dst": "~/.config/atom/afile" } ] }
JSONC

  local stow="$TEST_DIR/.stow/alex"
  # Declared order is zed-first to prove the lib re-sorts.
  run cg_build_plan "$TEST_DIR/programs" \
    '{"_fixture/zed":"configs","_fixture/atom":"configs"}' \
    "$stow" '["zed","atom"]'
  [ "$status" -eq 0 ]

  echo "$output" | jq -e 'length == 2'
  echo "$output" | jq --arg d "$stow/.config/atom/afile" \
    -e '.[0].dst_in_stow_tree == $d'
  echo "$output" | jq --arg d "$stow/.config/zed/zfile" \
    -e '.[1].dst_in_stow_tree == $d'
}

@test "plan: mode passes through when present, omitted when absent" {
  local d="$TEST_DIR/programs/_fixture/ssh/configs"
  mkdir -p "$d"
  printf 'k\n' > "$d/key"
  printf 'c\n' > "$d/cfg"
  cat > "$d/manifest.jsonc" <<'JSONC'
{ "files": [
  { "src": "key", "dst": "~/.ssh/key", "mode": "0600" },
  { "src": "cfg", "dst": "~/.ssh/cfg" }
] }
JSONC

  local stow="$TEST_DIR/.stow/alex"
  run cg_build_plan "$TEST_DIR/programs" \
    '{"_fixture/ssh":"configs"}' "$stow" '["ssh"]'
  [ "$status" -eq 0 ]

  echo "$output" | jq -e 'length == 2'
  # Sorted by dst: cfg first, key second
  echo "$output" | jq -e '.[0].mode == null or (.[0] | has("mode") | not)'
  echo "$output" | jq -e '.[1].mode == "0600"'
}

@test "plan: identical inputs produce byte-identical output" {
  for n in delta charlie alpha bravo; do
    local d="$TEST_DIR/programs/_fixture/$n/configs"
    mkdir -p "$d"
    printf 'x\n' > "$d/file"
    cat > "$d/manifest.jsonc" <<JSONC
{ "files": [ { "src": "file", "dst": "~/.config/$n/file" } ] }
JSONC
  done

  local resolved='{"_fixture/delta":"configs","_fixture/charlie":"configs","_fixture/alpha":"configs","_fixture/bravo":"configs"}'
  local stow="$TEST_DIR/.stow/alex"
  local declared='["delta","charlie","alpha","bravo"]'

  run cg_build_plan "$TEST_DIR/programs" "$resolved" "$stow" "$declared"
  [ "$status" -eq 0 ]
  local first="$output"

  run cg_build_plan "$TEST_DIR/programs" "$resolved" "$stow" "$declared"
  [ "$status" -eq 0 ]
  [ "$first" = "$output" ]
}

@test "plan: shared system program, two users with different variants" {
  local base="$TEST_DIR/programs/_fixture/shared"
  mkdir -p "$base/configs@minimal" "$base/configs@gaudy"
  printf 'm\n' > "$base/configs@minimal/file"
  printf 'g\n' > "$base/configs@gaudy/file"
  cat > "$base/configs@minimal/manifest.jsonc" <<'JSONC'
{ "files": [ { "src": "file", "dst": "~/.config/shared/file" } ] }
JSONC
  cat > "$base/configs@gaudy/manifest.jsonc" <<'JSONC'
{ "files": [ { "src": "file", "dst": "~/.config/shared/file" } ] }
JSONC

  # User alex picks minimal; user beth picks gaudy. Same declared set
  # ("shared" is a system program), same stow root pattern, different
  # resolved maps → different plans.
  local stow_alex="$TEST_DIR/.stow/alex"
  local stow_beth="$TEST_DIR/.stow/beth"

  run cg_build_plan "$TEST_DIR/programs" \
    '{"_fixture/shared":"configs@minimal"}' "$stow_alex" '["shared"]'
  [ "$status" -eq 0 ]
  local alex_plan="$output"

  run cg_build_plan "$TEST_DIR/programs" \
    '{"_fixture/shared":"configs@gaudy"}' "$stow_beth" '["shared"]'
  [ "$status" -eq 0 ]
  local beth_plan="$output"

  echo "$alex_plan" | jq -e '.[0].src_abs | test("configs@minimal/file$")'
  echo "$beth_plan" | jq -e '.[0].src_abs | test("configs@gaudy/file$")'
  [ "$alex_plan" != "$beth_plan" ]
}

@test "plan: declared program absent from resolved map → empty plan" {
  # System program declared in Host Config but with no configs/ tree on
  # disk → resolver omits it → plan must not include it.
  local stow="$TEST_DIR/.stow/alex"
  run cg_build_plan "$TEST_DIR/programs" '{}' "$stow" '["sops"]'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 0'
}
