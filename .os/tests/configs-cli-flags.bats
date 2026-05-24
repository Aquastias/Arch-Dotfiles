#!/usr/bin/env bats
# Tests for .os/tools/generate-configs.sh — CLI flag matrix.

CLI="$BATS_TEST_DIRNAME/../tools/generate-configs.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  PROGS="$TEST_DIR/programs"
  mkdir -p "$PROGS/_fixture/hello/configs"
  printf 'hi\n' > "$PROGS/_fixture/hello/configs/greeting"
  cat > "$PROGS/_fixture/hello/configs/manifest.jsonc" <<'JSONC'
{ "files": [ { "src": "greeting",
               "dst": "~/.config/hello/greeting" } ] }
JSONC
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "cli: --dry-run --user prints plan and writes nothing" {
  run env PROGRAMS_ROOT="$PROGS" "$CLI" --dry-run --user alex
  [ "$status" -eq 0 ]
  [[ "$output" == *"$PROGS/_fixture/hello/configs/greeting"* ]]
  [[ "$output" == *".config/hello/greeting"* ]]
  [ ! -e "$HOME/.dotfiles/.stow/alex" ]
}

@test "cli: --validate-only --user exits 0, no plan output, no writes" {
  run env PROGRAMS_ROOT="$PROGS" "$CLI" --validate-only --user alex
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$HOME/.dotfiles/.stow/alex" ]
}

@test "cli: --validate-only --user exits non-zero on invalid manifest" {
  printf '{ not json }\n' > \
    "$PROGS/_fixture/hello/configs/manifest.jsonc"
  run env PROGRAMS_ROOT="$PROGS" "$CLI" --validate-only --user alex
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/.dotfiles/.stow/alex" ]
}

@test "cli: --validate-only without --user validates manifests globally" {
  run env PROGRAMS_ROOT="$PROGS" "$CLI" --validate-only
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "cli: --validate-only without --user fails on invalid manifest" {
  printf '{ broken\n' > "$PROGS/_fixture/hello/configs/manifest.jsonc"
  run env PROGRAMS_ROOT="$PROGS" "$CLI" --validate-only
  [ "$status" -ne 0 ]
}

@test "cli: --dry-run --user exits non-zero on invalid manifest" {
  printf '{ not json }\n' > \
    "$PROGS/_fixture/hello/configs/manifest.jsonc"
  run env PROGRAMS_ROOT="$PROGS" "$CLI" --dry-run --user alex
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/.dotfiles/.stow/alex" ]
}

@test "cli: --dry-run output is stable across runs" {
  # Two extra fixtures so ordering is non-trivial
  mkdir -p "$PROGS/_fixture/alpha/configs" "$PROGS/_fixture/beta/configs"
  printf 'a\n' > "$PROGS/_fixture/alpha/configs/a"
  printf 'b\n' > "$PROGS/_fixture/beta/configs/b"
  cat > "$PROGS/_fixture/alpha/configs/manifest.jsonc" <<'JSONC'
{ "files": [ { "src": "a", "dst": "~/.config/alpha/a" } ] }
JSONC
  cat > "$PROGS/_fixture/beta/configs/manifest.jsonc" <<'JSONC'
{ "files": [ { "src": "b", "dst": "~/.config/beta/b" } ] }
JSONC

  run env PROGRAMS_ROOT="$PROGS" "$CLI" --dry-run --user alex
  [ "$status" -eq 0 ]
  first="$output"

  run env PROGRAMS_ROOT="$PROGS" "$CLI" --dry-run --user alex
  [ "$status" -eq 0 ]
  [ "$first" = "$output" ]
}

@test "cli: --dry-run --validate-only together rejected (exit 2)" {
  run env PROGRAMS_ROOT="$PROGS" "$CLI" --dry-run --validate-only --user alex
  [ "$status" -eq 2 ]
}
