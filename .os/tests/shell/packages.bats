#!/usr/bin/env bats
# Tests for .os/lib/shell/packages.sh — package_installed helper.

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"
  export TEST_DIR STUB_BIN

  # shellcheck source=../../lib/shell/packages.sh
  source "$BATS_TEST_DIRNAME/../../lib/shell/packages.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

_stub_pacman() {
  local exit_code="$1"
  cat > "$STUB_BIN/pacman" <<EOF
#!/usr/bin/env bash
exit $exit_code
EOF
  chmod +x "$STUB_BIN/pacman"
}

@test "package_installed: returns 0 when pacman -Q exits 0" {
  _stub_pacman 0
  PATH="$STUB_BIN:$PATH" run package_installed somepkg
  [ "$status" -eq 0 ]
}

@test "package_installed: returns non-zero when pacman -Q exits 1" {
  _stub_pacman 1
  PATH="$STUB_BIN:$PATH" run package_installed missingpkg
  [ "$status" -ne 0 ]
}
