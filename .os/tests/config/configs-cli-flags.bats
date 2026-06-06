#!/usr/bin/env bats
# Tests for .os/tools/generate-configs.sh — CLI flag matrix.

CLI="$BATS_TEST_DIRNAME/../../tools/generate-configs.sh"

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

  # Minimal OS_DIR seed so the CLI's host/user merge picks up declared
  # programs without contaminating from the real .os/ tree.
  export OS_DIR="$TEST_DIR/osdir"
  mkdir -p "$OS_DIR/users/core" "$OS_DIR/hosts/core"
  cat > "$OS_DIR/users/core/config.jsonc" <<'JSONC'
{ "programs": ["hello", "alpha", "beta"] }
JSONC
  cat > "$OS_DIR/hosts/core/config.jsonc" <<'JSONC'
{ "system_programs": [] }
JSONC
  ln -s "$BATS_TEST_DIRNAME/../../lib" "$OS_DIR/lib"
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

@test "cli: --user resolves House Default from core, override from user" {
  mkdir -p "$OS_DIR/users/alex" \
           "$OS_DIR/programs/_fixture/alpha/configs" \
           "$OS_DIR/programs/_fixture/alpha/configs@minimal" \
           "$OS_DIR/programs/_fixture/alpha/configs@gaudy" \
           "$OS_DIR/programs/_fixture/bravo/configs" \
           "$OS_DIR/programs/_fixture/bravo/configs@minimal"

  cat > "$OS_DIR/users/core/config.jsonc" <<'JSONC'
{ "programs": ["alpha", "bravo"],
  "variants": { "alpha": "gaudy", "bravo": "minimal" } }
JSONC
  cat > "$OS_DIR/users/alex/config.jsonc" <<'JSONC'
{ "variants": { "alpha": "minimal" } }
JSONC

  for d in \
    "$OS_DIR/programs/_fixture/alpha/configs" \
    "$OS_DIR/programs/_fixture/alpha/configs@minimal" \
    "$OS_DIR/programs/_fixture/alpha/configs@gaudy" \
    "$OS_DIR/programs/_fixture/bravo/configs" \
    "$OS_DIR/programs/_fixture/bravo/configs@minimal"; do
    printf 'x\n' > "$d/file"
    cat > "$d/manifest.jsonc" <<JSONC
{ "files": [ { "src": "file",
               "dst": "~/.config/$(basename "$(dirname "$d")")/$(basename "$d")" } ] }
JSONC
  done

  run env PROGRAMS_ROOT="$OS_DIR/programs" \
      "$CLI" --dry-run --user alex
  [ "$status" -eq 0 ]
  # alpha: user override wins (minimal), not core's gaudy
  [[ "$output" == *"alpha/configs@minimal/file"* ]]
  [[ "$output" != *"alpha/configs@gaudy/file"* ]]
  # bravo: House Default from core (minimal) applied
  [[ "$output" == *"bravo/configs@minimal/file"* ]]
  [[ "$output" != *"bravo/configs/file"* ]]
}

@test "cli: errors are emitted via print_status (with [ERROR] prefix)" {
  printf '{ not json }\n' > \
    "$PROGS/_fixture/hello/configs/manifest.jsonc"
  run env PROGRAMS_ROOT="$PROGS" "$CLI" --validate-only --user alex
  [ "$status" -ne 0 ]
  [[ "$output" == *"[ERROR]"* ]]
  [[ "$output" == *"manifest invalid"* ]]
}

@test "cli: aborts with non-zero and no writes when conflict detected" {
  # Legacy stow tree owns ~/.config/hello/greeting already.
  local LEG="$TEST_DIR/legacy"
  mkdir -p "$LEG/.config/hello"
  printf 'legacy\n' > "$LEG/.config/hello/greeting"

  run env PROGRAMS_ROOT="$PROGS" LEGACY_ROOT="$LEG" \
      "$CLI" --user alex
  [ "$status" -ne 0 ]
  [[ "$output" == *"$PROGS/_fixture/hello/configs/greeting"* ]]
  [[ "$output" == *"$LEG/.config/hello/greeting"* ]]
  [ ! -e "$HOME/.dotfiles/.stow/alex" ]
}

@test "cli: --dry-run --user aborts on legacy conflict (non-zero, no writes)" {
  local LEG="$TEST_DIR/legacy"
  mkdir -p "$LEG/.config/hello"
  printf 'legacy\n' > "$LEG/.config/hello/greeting"

  run env PROGRAMS_ROOT="$PROGS" LEGACY_ROOT="$LEG" \
      "$CLI" --dry-run --user alex
  [ "$status" -ne 0 ]
  [[ "$output" == *"$PROGS/_fixture/hello/configs/greeting"* ]]
  [[ "$output" == *"$LEG/.config/hello/greeting"* ]]
  [ ! -e "$HOME/.dotfiles/.stow/alex" ]
}

@test "cli: --validate-only --user fails on missing variant directory" {
  mkdir -p "$OS_DIR/users/alex"
  cat > "$OS_DIR/users/alex/config.jsonc" <<'JSONC'
{ "variants": { "hello": "ghost" } }
JSONC

  run env PROGRAMS_ROOT="$PROGS" "$CLI" --validate-only --user alex
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/.dotfiles/.stow/alex" ]
}
