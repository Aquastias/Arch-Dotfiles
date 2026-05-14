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
  # ssh-keygen: output a fake public key (ignores -y -f args)
  printf '#!/usr/bin/env bash\necho "ssh-ed25519 AAAAFAKE testkey"\n' \
    > "$TEST_DIR/bin/ssh-keygen"
  # chown: capture calls for assertion
  printf '#!/usr/bin/env bash\necho "$@" >> "%s/chown_calls"\n' "$TEST_DIR" \
    > "$TEST_DIR/bin/chown"

  chmod +x "$TEST_DIR/bin"/*
  export PATH="$TEST_DIR/bin:$PATH"
  export HOME_BASE="$TEST_DIR/home"
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

# ── #03: SSH identity deployment ──────────────────────────────────────────────

@test "no .ssh dir when ssh_identity_private_key absent" {
  printf '{"password":"pw"}\n' > "$TEST_DIR/user-secrets.json"
  run _run_create_user "alice" "/bin/bash" "" "pw" "$TEST_DIR/user-secrets.json"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_DIR/home/alice/.ssh" ]
}

@test "writes private key to id_ed25519 when key type absent (default)" {
  printf '{"ssh_identity_private_key":"FAKEKEY"}\n' > "$TEST_DIR/user-secrets.json"
  run _run_create_user "alice" "/bin/bash" "" "pw" "$TEST_DIR/user-secrets.json"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/home/alice/.ssh/id_ed25519")" = "FAKEKEY" ]
}

@test "writes private key to id_rsa when key type is rsa" {
  printf '{"ssh_identity_private_key":"FAKEKEY","ssh_identity_key_type":"rsa"}\n' \
    > "$TEST_DIR/user-secrets.json"
  run _run_create_user "alice" "/bin/bash" "" "pw" "$TEST_DIR/user-secrets.json"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/home/alice/.ssh/id_rsa")" = "FAKEKEY" ]
}

@test "writes private key to id_ecdsa when key type is ecdsa" {
  printf '{"ssh_identity_private_key":"FAKEKEY","ssh_identity_key_type":"ecdsa"}\n' \
    > "$TEST_DIR/user-secrets.json"
  run _run_create_user "alice" "/bin/bash" "" "pw" "$TEST_DIR/user-secrets.json"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/home/alice/.ssh/id_ecdsa")" = "FAKEKEY" ]
}

@test "writes private key to id_ed25519 when key type is ed25519 explicitly" {
  printf '{"ssh_identity_private_key":"FAKEKEY","ssh_identity_key_type":"ed25519"}\n' \
    > "$TEST_DIR/user-secrets.json"
  run _run_create_user "alice" "/bin/bash" "" "pw" "$TEST_DIR/user-secrets.json"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/home/alice/.ssh/id_ed25519")" = "FAKEKEY" ]
}

@test "private key file has permissions 600" {
  printf '{"ssh_identity_private_key":"FAKEKEY"}\n' > "$TEST_DIR/user-secrets.json"
  run _run_create_user "alice" "/bin/bash" "" "pw" "$TEST_DIR/user-secrets.json"
  [ "$status" -eq 0 ]
  [ "$(stat -c '%a' "$TEST_DIR/home/alice/.ssh/id_ed25519")" = "600" ]
}

@test "public key file has permissions 644" {
  printf '{"ssh_identity_private_key":"FAKEKEY"}\n' > "$TEST_DIR/user-secrets.json"
  run _run_create_user "alice" "/bin/bash" "" "pw" "$TEST_DIR/user-secrets.json"
  [ "$status" -eq 0 ]
  [ "$(stat -c '%a' "$TEST_DIR/home/alice/.ssh/id_ed25519.pub")" = "644" ]
}

@test "public key content comes from ssh-keygen -y" {
  printf '{"ssh_identity_private_key":"FAKEKEY"}\n' > "$TEST_DIR/user-secrets.json"
  run _run_create_user "alice" "/bin/bash" "" "pw" "$TEST_DIR/user-secrets.json"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/home/alice/.ssh/id_ed25519.pub")" = "ssh-ed25519 AAAAFAKE testkey" ]
}

@test "chown called with username on ssh dir and key files" {
  printf '{"ssh_identity_private_key":"FAKEKEY"}\n' > "$TEST_DIR/user-secrets.json"
  run _run_create_user "alice" "/bin/bash" "" "pw" "$TEST_DIR/user-secrets.json"
  [ "$status" -eq 0 ]
  grep -q "alice:alice" "$TEST_DIR/chown_calls"
}
