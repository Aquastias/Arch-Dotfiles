#!/usr/bin/env bats
# Tests for lib/chroot/password.sh — root password with optional host secrets

setup() {
  TEST_DIR="$(mktemp -d)"
  mkdir -p "$TEST_DIR/bin"

  # sed: no-op (sudoers modification not under test)
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_DIR/bin/sed"
  # chpasswd: capture stdin
  printf '#!/usr/bin/env bash\ncat > "%s/chpasswd_input"\n' "$TEST_DIR" \
    > "$TEST_DIR/bin/chpasswd"

  chmod +x "$TEST_DIR/bin"/*
  export PATH="$TEST_DIR/bin:$PATH"
}

teardown() { rm -rf "$TEST_DIR"; }

# ── #04: root password from host secrets ──────────────────────────────────────

@test "uses ROOT_PW env when HOST_SECRETS_FILE not set" {
  run env ROOT_PW="envpassword" \
    bash "$BATS_TEST_DIRNAME/../../lib/chroot/password.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/chpasswd_input")" = "root:envpassword" ]
}

@test "falls back to ROOT_PW when HOST_SECRETS_FILE has no root_password" {
  printf '{"other_field":"value"}\n' > "$TEST_DIR/host-secrets.json"
  run env ROOT_PW="fallback" HOST_SECRETS_FILE="$TEST_DIR/host-secrets.json" \
    bash "$BATS_TEST_DIRNAME/../../lib/chroot/password.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/chpasswd_input")" = "root:fallback" ]
}

@test "uses root_password from HOST_SECRETS_FILE when field is present" {
  printf '{"root_password":"s3cr3troot"}\n' > "$TEST_DIR/host-secrets.json"
  run env ROOT_PW="12345" HOST_SECRETS_FILE="$TEST_DIR/host-secrets.json" \
    bash "$BATS_TEST_DIRNAME/../../lib/chroot/password.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/chpasswd_input")" = "root:s3cr3troot" ]
}
