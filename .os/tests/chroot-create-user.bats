#!/usr/bin/env bats
# Tests for lib/chroot/create-user.sh — user creation with optional secrets

setup() {
  TEST_DIR="$(mktemp -d)"
  mkdir -p "$TEST_DIR/bin"

  # User does not exist: id exits 1
  printf '#!/usr/bin/env bash\nexit 1\n' > "$TEST_DIR/bin/id"
  # useradd / usermod: no-ops
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_DIR/bin/useradd"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_DIR/bin/usermod"
  # getent: groups exist
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_DIR/bin/getent"
  # chpasswd: capture stdin
  printf '#!/usr/bin/env bash\ncat > "%s/chpasswd_input"\n' "$TEST_DIR" \
    > "$TEST_DIR/bin/chpasswd"

  chmod +x "$TEST_DIR/bin"/*
  export PATH="$TEST_DIR/bin:$PATH"
}

teardown() { rm -rf "$TEST_DIR"; }

_run_create_user() {
  bash "$BATS_TEST_DIRNAME/../lib/chroot/create-user.sh" "$@"
}

# ── #02: password from secrets ────────────────────────────────────────────────

@test "uses PASSWORD arg when SECRETS_FILE not given" {
  run _run_create_user "alice" "/bin/bash" "" "mypassword"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/chpasswd_input")" = "alice:mypassword" ]
}

@test "falls back to PASSWORD arg when SECRETS_FILE has no password field" {
  printf '{"ssh_identity_private_key":"dummykey"}\n' > "$TEST_DIR/user-secrets.json"
  run _run_create_user "alice" "/bin/bash" "" "fallback" "$TEST_DIR/user-secrets.json"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/chpasswd_input")" = "alice:fallback" ]
}

@test "uses password from SECRETS_FILE when password field is present" {
  printf '{"password":"s3cr3tpw"}\n' > "$TEST_DIR/user-secrets.json"
  run _run_create_user "alice" "/bin/bash" "" "12345" "$TEST_DIR/user-secrets.json"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/chpasswd_input")" = "alice:s3cr3tpw" ]
}
