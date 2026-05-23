#!/usr/bin/env bats
# Tests for .os/lib/shell/permissions.sh — check_root helper.

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"
  export TEST_DIR STUB_BIN

  # shellcheck source=../lib/shell/permissions.sh
  source "$BATS_TEST_DIRNAME/../lib/shell/permissions.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

_stub_id() {
  local uid="$1"
  cat > "$STUB_BIN/id" <<EOF
#!/usr/bin/env bash
[[ "\$1" == "-u" ]] && echo "$uid" && exit 0
exit 1
EOF
  chmod +x "$STUB_BIN/id"
}

@test "check_root: non-root (uid 1000) exits 1 with stderr message" {
  _stub_id 1000
  PATH="$STUB_BIN:$PATH" run check_root
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be run as root"* ]]
}

@test "check_root: root (uid 0) exits 0 silently" {
  _stub_id 0
  PATH="$STUB_BIN:$PATH" run check_root
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
