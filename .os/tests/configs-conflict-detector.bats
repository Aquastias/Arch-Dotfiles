#!/usr/bin/env bats
# Tests for lib/configs-generator.sh — Conflict Detector.

setup() {
  TEST_DIR="$(mktemp -d)"
  LEGACY="$TEST_DIR/legacy"
  STOW="$TEST_DIR/stow"
  export HOME="$TEST_DIR/home"
  mkdir -p "$LEGACY" "$STOW" "$HOME"
  # shellcheck source=../lib/configs-generator.sh
  source "$BATS_TEST_DIRNAME/../lib/configs-generator.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Build a plan JSON array from "src<TAB>dst" lines on stdin.
plan_from_pairs() {
  jq -Rsc '
    split("\n")
    | map(select(length > 0)
          | split("\t")
          | {src_abs: .[0], dst_in_stow_tree: .[1]})
  '
}

@test "detector: empty when no plan dst overlaps legacy package contents" {
  mkdir -p "$LEGACY/.config/foo"
  printf 'x\n' > "$LEGACY/.config/foo/bar"
  local plan
  plan="$(printf '/src/a\t%s\n' "$STOW/.config/other/baz" | plan_from_pairs)"

  run cg_detect_conflicts "$plan" "$LEGACY" "$STOW"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. == []'
}

@test "detector: flags conflict when plan dst matches legacy package path" {
  mkdir -p "$LEGACY/.config/kitty"
  printf 'leg\n' > "$LEGACY/.config/kitty/kitty.conf"
  local plan
  plan="$(printf '/src/kitty.conf\t%s\n' \
    "$STOW/.config/kitty/kitty.conf" | plan_from_pairs)"

  run cg_detect_conflicts "$plan" "$LEGACY" "$STOW"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 1'
  echo "$output" | jq -e '.[0].plan_src == "/src/kitty.conf"'
  echo "$output" \
    | jq -e --arg l "$LEGACY/.config/kitty/kitty.conf" '.[0].legacy_src == $l'
}

@test "detector: flags every conflict in a multi-conflict plan" {
  mkdir -p "$LEGACY/.config" "$LEGACY/.zsh"
  printf '1\n' > "$LEGACY/.config/a"
  printf '2\n' > "$LEGACY/.zsh/b"
  local plan
  plan="$(printf '%s\n' \
    "/src/a	$STOW/.config/a" \
    "/src/b	$STOW/.zsh/b" \
    | plan_from_pairs)"

  run cg_detect_conflicts "$plan" "$LEGACY" "$STOW"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 2'
}

@test "detector: same-suffix in different package is NOT a conflict" {
  mkdir -p "$LEGACY/.zsh"
  printf '1\n' > "$LEGACY/.zsh/foo"
  local plan
  plan="$(printf '/src/foo\t%s\n' "$STOW/.config/foo" | plan_from_pairs)"

  run cg_detect_conflicts "$plan" "$LEGACY" "$STOW"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. == []'
}

@test "detector: legacy_packages helper excludes repo metadata dirs" {
  mkdir -p "$LEGACY/.config" "$LEGACY/.zsh" "$LEGACY/.git" \
           "$LEGACY/.os" "$LEGACY/.scratch" "$LEGACY/.stow" \
           "$LEGACY/docs"

  run cg_legacy_packages "$LEGACY"
  [ "$status" -eq 0 ]
  [[ "$output" == *".config"* ]]
  [[ "$output" == *".zsh"* ]]
  [[ "$output" == *"docs"* ]]
  [[ "$output" != *".git"* ]]
  [[ "$output" != *".os"* ]]
  [[ "$output" != *".scratch"* ]]
  [[ "$output" != *".stow"* ]]
}

@test "detector: backwards-compat — empty legacy_root + stow_root returns []" {
  local plan='[{"src_abs":"/x","dst_in_stow_tree":"/y/.config/hello"}]'

  run cg_detect_conflicts "$plan" "" ""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. == []'
}
