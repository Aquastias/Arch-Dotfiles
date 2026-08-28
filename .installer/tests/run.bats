#!/usr/bin/env bats
# Tests for tests/run.sh — bats runner entrypoint

setup() {
  TEST_DIR="$(mktemp -d)"
  mkdir -p "$TEST_DIR/bin" "$TEST_DIR/bats/bin"

  # Externals run.sh needs. Symlinked so we control whether parallel
  # is on PATH without losing bash/dirname/nproc.
  for bin in bash dirname nproc; do
    ln -s "$(command -v "$bin")" "$TEST_DIR/bin/$bin"
  done

  RUN_SH="$BATS_TEST_DIRNAME/run.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "aborts with pacman hint when parallel is missing" {
  PATH="$TEST_DIR/bin" run "$TEST_DIR/bin/bash" "$RUN_SH"
  [ "$status" -ne 0 ]
  [[ "$output" == *"pacman -S parallel"* ]]
}

@test "invokes bats with --jobs nproc when parallel is present" {
  # Stub parallel (presence only) and bats (log argv).
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_DIR/bin/parallel"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/argv"\n' \
    "$TEST_DIR" > "$TEST_DIR/bats/bin/bats"
  chmod +x "$TEST_DIR/bin/parallel" "$TEST_DIR/bats/bin/bats"

  PATH="$TEST_DIR/bin" BATS_DIR="$TEST_DIR/bats" \
    run "$TEST_DIR/bin/bash" "$RUN_SH"

  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/argv" ]
  run head -2 "$TEST_DIR/argv"
  [ "${lines[0]}" = "--jobs" ]
  [ "${lines[1]}" = "$(nproc)" ]
}
