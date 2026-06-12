#!/usr/bin/env bats
# Tests for lib/config/generator.sh — Variant Resolver.

setup() {
  TEST_DIR="$(mktemp -d)"
  # shellcheck source=../../lib/config/generator.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/generator.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

write_manifest() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' '{ "files": [] }' > "$1"
}

@test "resolver: no variants declared → migrated programs resolve to configs/" {
  write_manifest "$TEST_DIR/programs/cat-a/prog-a/configs/manifest.jsonc"
  write_manifest "$TEST_DIR/programs/cat-b/prog-b/configs/manifest.jsonc"

  run cg_resolve_variants "$TEST_DIR/programs" '{}'
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '."cat-a/prog-a" == "configs"'
  echo "$output" | jq -e '."cat-b/prog-b" == "configs"'
}

@test "resolver: configs/ without manifest.jsonc errors and names program" {
  mkdir -p "$TEST_DIR/programs/legacy/prog-x/configs"
  printf 'data\n' > "$TEST_DIR/programs/legacy/prog-x/configs/foo.conf"

  run cg_resolve_variants "$TEST_DIR/programs" '{}'
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"legacy/prog-x"* ]] || [[ "$output" == *"legacy/prog-x"* ]]
  [[ "$stderr" == *"manifest.jsonc"* ]] || [[ "$output" == *"manifest.jsonc"* ]]
}

@test "resolver: configs@<x>/ without manifest.jsonc errors and names variant" {
  write_manifest "$TEST_DIR/programs/term/kitty/configs/manifest.jsonc"
  mkdir -p "$TEST_DIR/programs/term/kitty/configs@minimal"
  printf 'x\n' > "$TEST_DIR/programs/term/kitty/configs@minimal/file"

  run cg_resolve_variants "$TEST_DIR/programs" '{"kitty":"minimal"}'
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"term/kitty"* ]] || [[ "$output" == *"term/kitty"* ]]
  [[ "$stderr" == *"minimal"* ]]    || [[ "$output" == *"minimal"* ]]
  [[ "$stderr" == *"manifest.jsonc"* ]] || [[ "$output" == *"manifest.jsonc"* ]]
}

@test "resolver: declared variant resolves to matching configs@<x>/" {
  write_manifest "$TEST_DIR/programs/term/kitty/configs/manifest.jsonc"
  write_manifest "$TEST_DIR/programs/term/kitty/configs@minimal/manifest.jsonc"

  run cg_resolve_variants "$TEST_DIR/programs" '{"kitty":"minimal"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '."term/kitty" == "configs@minimal"'
}

@test "resolver: variants[<x>] = \"default\" resolves to configs/" {
  write_manifest "$TEST_DIR/programs/term/kitty/configs/manifest.jsonc"
  write_manifest "$TEST_DIR/programs/term/kitty/configs@gaudy/manifest.jsonc"

  run cg_resolve_variants "$TEST_DIR/programs" '{"kitty":"default"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '."term/kitty" == "configs"'
}

@test "resolver: declared variant with no matching dir errors" {
  write_manifest "$TEST_DIR/programs/term/kitty/configs/manifest.jsonc"

  run cg_resolve_variants "$TEST_DIR/programs" '{"kitty":"ghost"}'
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"kitty"* ]] || [[ "$output" == *"kitty"* ]]
  [[ "$stderr" == *"ghost"* ]] || [[ "$output" == *"ghost"* ]]
}

@test "resolver: only configs@*/ and no variant declared errors" {
  write_manifest "$TEST_DIR/programs/term/zsh/configs@minimal/manifest.jsonc"
  write_manifest "$TEST_DIR/programs/term/zsh/configs@gaudy/manifest.jsonc"

  run cg_resolve_variants "$TEST_DIR/programs" '{}'
  [ "$status" -ne 0 ]
}

@test "resolver: configs@default/ on disk is illegal" {
  write_manifest "$TEST_DIR/programs/term/kitty/configs/manifest.jsonc"
  write_manifest "$TEST_DIR/programs/term/kitty/configs@default/manifest.jsonc"

  run cg_resolve_variants "$TEST_DIR/programs" '{}'
  [ "$status" -ne 0 ]
}

@test "resolver: variant dir name violating [a-z0-9-]+ errors" {
  write_manifest "$TEST_DIR/programs/term/kitty/configs/manifest.jsonc"
  write_manifest "$TEST_DIR/programs/term/kitty/configs@FOO/manifest.jsonc"

  run cg_resolve_variants "$TEST_DIR/programs" '{}'
  [ "$status" -ne 0 ]
}

@test "resolver: house defaults override per-key via load_user_profile" {
  # shellcheck source=../../lib/config/profile.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/profile.sh"
  export OS_DIR="$TEST_DIR"

  mkdir -p "$TEST_DIR/users/core" "$TEST_DIR/users/alex"
  cat > "$TEST_DIR/users/core/profile.jsonc" <<'JSONC'
{ "variants": { "kitty": "minimal", "zsh": "minimal" } }
JSONC
  cat > "$TEST_DIR/users/alex/profile.jsonc" <<'JSONC'
{ "variants": { "zsh": "gaudy" } }
JSONC

  write_manifest "$TEST_DIR/programs/term/kitty/configs/manifest.jsonc"
  write_manifest "$TEST_DIR/programs/term/kitty/configs@minimal/manifest.jsonc"
  write_manifest "$TEST_DIR/programs/term/zsh/configs/manifest.jsonc"
  write_manifest "$TEST_DIR/programs/term/zsh/configs@minimal/manifest.jsonc"
  write_manifest "$TEST_DIR/programs/term/zsh/configs@gaudy/manifest.jsonc"

  local merged variants
  merged="$(load_user_profile alex)"
  variants="$(jq -c '.variants' <<<"$merged")"

  run cg_resolve_variants "$TEST_DIR/programs" "$variants"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '."term/kitty" == "configs@minimal"'
  echo "$output" | jq -e '."term/zsh"   == "configs@gaudy"'
}
