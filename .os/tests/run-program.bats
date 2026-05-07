#!/usr/bin/env bats
# Tests for .os/lib/run-program.sh — staging guard + Shell Stdlib sourcing.

setup() {
  TEST_DIR="$(mktemp -d)"
  RUN_PROGRAM="$BATS_TEST_DIRNAME/../lib/run-program.sh"
  mkdir -p "$TEST_DIR/lib"
  printf '#!/usr/bin/env bash\nstdlib_marker() { echo from-stdlib; }\n' \
    > "$TEST_DIR/lib/shell-stdlib.sh"
  export SHELL_COMMONS="$TEST_DIR/lib"
  export OS_DIR="$TEST_DIR"
  export PROGRAMS="$TEST_DIR/programs"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "exits 99 when SHELL_COMMONS is unset" {
  unset SHELL_COMMONS
  run bash "$RUN_PROGRAM" /nonexistent/install.sh
  [ "$status" -eq 99 ]
  [[ "$output" =~ "SHELL_COMMONS not set" ]]
}

@test "exits 99 when shell-stdlib.sh is missing" {
  rm "$TEST_DIR/lib/shell-stdlib.sh"
  printf '#!/usr/bin/env bash\n' > "$TEST_DIR/install.sh"
  run bash "$RUN_PROGRAM" "$TEST_DIR/install.sh"
  [ "$status" -eq 99 ]
  [[ "$output" =~ "shell-stdlib.sh not readable" ]]
}

@test "exits 99 when install.sh is missing" {
  run bash "$RUN_PROGRAM" "$TEST_DIR/missing.sh"
  [ "$status" -eq 99 ]
  [[ "$output" =~ "install.sh not readable" ]]
}

@test "sources stdlib then sources install.sh in same shell" {
  cat > "$TEST_DIR/install.sh" <<'EOF'
stdlib_marker
echo "got SHELL_COMMONS=${SHELL_COMMONS}"
EOF
  run bash "$RUN_PROGRAM" "$TEST_DIR/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "from-stdlib" ]]
  [[ "$output" =~ "got SHELL_COMMONS=$TEST_DIR/lib" ]]
}

@test "install.sh failure propagates non-zero" {
  printf '#!/usr/bin/env bash\nexit 7\n' > "$TEST_DIR/install.sh"
  run bash "$RUN_PROGRAM" "$TEST_DIR/install.sh"
  [ "$status" -eq 7 ]
}

@test "install.sh inherits set -e from runner (unhandled error aborts)" {
  cat > "$TEST_DIR/install.sh" <<'EOF'
false
echo "should not print"
EOF
  run bash "$RUN_PROGRAM" "$TEST_DIR/install.sh"
  [ "$status" -ne 0 ]
  [[ ! "$output" =~ "should not print" ]]
}
