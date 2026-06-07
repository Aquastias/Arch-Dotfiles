#!/usr/bin/env bats
# Tests for the VM_FIXTURE_FILES staging hook in .os/vm/lib/core.sh.
#
# Drives `_stage_fixture_files` in isolation — no libvirt, no HTTP server,
# no python. Each test sets VM_SCRIPT_DIR + CACHE_DIR + VM_FIXTURE_FILES
# in a child shell, sources the harness, invokes the staging fn, and
# asserts on the resulting CACHE_DIR contents (or the error stream).

HARNESS="$BATS_TEST_DIRNAME/../../vm/lib/core.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export VM_SCRIPT_DIR="$TEST_DIR/script-dir"
  export CACHE_DIR="$TEST_DIR/cache"
  mkdir -p "$VM_SCRIPT_DIR" "$CACHE_DIR"
}

teardown() { rm -rf "$TEST_DIR"; }

# Run _stage_fixture_files in a child bash. Arguments become entries in the
# VM_FIXTURE_FILES array (one per arg). `run` captures status/output.
_stage() {
  local args=""
  local a
  for a in "$@"; do args+=" '${a//\'/\'\\\'\'}'"; done
  run bash -c "
    set +e
    VM_SCRIPT_DIR='$VM_SCRIPT_DIR'
    CACHE_DIR='$CACHE_DIR'
    declare -a VM_FIXTURE_FILES=($args)
    # silence harness 'info' output during the test
    source '$HARNESS' >/dev/null 2>&1
    _stage_fixture_files
  "
}

# ── tracer bullet ─────────────────────────────────────────────────────────────

@test "stages one declared fixture into CACHE_DIR (happy path)" {
  printf 'hello fixture\n' > "$VM_SCRIPT_DIR/fix.txt"

  _stage "$VM_SCRIPT_DIR/fix.txt"
  [ "$status" -eq 0 ]
  [ -f "$CACHE_DIR/fix.txt" ]
  diff -q "$VM_SCRIPT_DIR/fix.txt" "$CACHE_DIR/fix.txt"
}

@test "stages multiple declared fixtures into CACHE_DIR" {
  printf 'a\n' > "$VM_SCRIPT_DIR/one.txt"
  printf 'b\n' > "$VM_SCRIPT_DIR/two.bin"

  _stage "$VM_SCRIPT_DIR/one.txt" "$VM_SCRIPT_DIR/two.bin"
  [ "$status" -eq 0 ]
  diff -q "$VM_SCRIPT_DIR/one.txt" "$CACHE_DIR/one.txt"
  diff -q "$VM_SCRIPT_DIR/two.bin" "$CACHE_DIR/two.bin"
}

@test "missing source file aborts with error naming the path" {
  _stage "$VM_SCRIPT_DIR/does-not-exist.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does-not-exist.txt"* ]]
  [[ "$output" == *missing* ]]
}

@test "duplicate basename across two entries aborts" {
  mkdir -p "$VM_SCRIPT_DIR/a" "$VM_SCRIPT_DIR/b"
  printf '1\n' > "$VM_SCRIPT_DIR/a/dup.txt"
  printf '2\n' > "$VM_SCRIPT_DIR/b/dup.txt"

  _stage "$VM_SCRIPT_DIR/a/dup.txt" "$VM_SCRIPT_DIR/b/dup.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *duplicate* ]]
  [[ "$output" == *dup.txt* ]]
}

@test "basename collision with installer 'run' aborts" {
  printf 'oops\n' > "$VM_SCRIPT_DIR/run"

  _stage "$VM_SCRIPT_DIR/run"
  [ "$status" -ne 0 ]
  [[ "$output" == *run* ]]
}

@test "unset VM_FIXTURE_FILES is a no-op (existing vm-*.sh unchanged)" {
  run bash -c "
    set +e
    VM_SCRIPT_DIR='$VM_SCRIPT_DIR'
    CACHE_DIR='$CACHE_DIR'
    unset VM_FIXTURE_FILES
    source '$HARNESS' >/dev/null 2>&1
    _stage_fixture_files
  "
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$CACHE_DIR")" ]
}

@test "empty VM_FIXTURE_FILES array is a no-op" {
  run bash -c "
    set +e
    VM_SCRIPT_DIR='$VM_SCRIPT_DIR'
    CACHE_DIR='$CACHE_DIR'
    declare -a VM_FIXTURE_FILES=()
    source '$HARNESS' >/dev/null 2>&1
    _stage_fixture_files
  "
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$CACHE_DIR")" ]
}

@test "relative path resolves against VM_SCRIPT_DIR not HARNESS_DIR" {
  printf 'rel\n' > "$VM_SCRIPT_DIR/rel-fix.txt"

  _stage "rel-fix.txt"
  [ "$status" -eq 0 ]
  diff -q "$VM_SCRIPT_DIR/rel-fix.txt" "$CACHE_DIR/rel-fix.txt"
}
