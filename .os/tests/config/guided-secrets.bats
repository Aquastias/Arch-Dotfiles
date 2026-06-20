#!/usr/bin/env bats
# Tests for lib/guided-secrets.sh — the Guided Installer's no-SOPS password
# injector (issue 07). It writes the *decrypted* secrets shape ({root_password},
# per-user {password, ssh_identity_private_key?}) to a tmpfs dir and points the
# back-end at the files via install-state's `.guided_passwords.*` key — the same
# downstream file contract the Secrets Module produces, but WITHOUT the
# `.secrets.*` key (which auto-activates the SOPS runtime program). Install-time
# only; passwords never enter the Config State, so Save/Export never carry them.
#
# Behaviour under test: the files written + the install-state seam.

setup() {
  TEST_DIR="$(mktemp -d)"
  info()  { :; }
  warn()  { :; }
  error() { echo "[error] $*" >&2; return 1; }
  export -f info warn error

  # shellcheck source=../../lib/install-state.sh
  source "$BATS_TEST_DIRNAME/../../lib/install-state.sh"
  # shellcheck source=../../lib/guided-secrets.sh
  source "$BATS_TEST_DIRNAME/../../lib/guided-secrets.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# ── tracer: a root password lands as a decrypted file + the no-SOPS seam ────

@test "guided_write_passwords: a root password writes host-secrets + .guided_passwords.host" {
  state="$TEST_DIR/install-state.json"; echo '{}' > "$state"
  dir="$TEST_DIR/secrets"

  guided_write_passwords '{"root_password":"hunter2"}' "$dir" "$state"

  # the decrypted file carries the root_password the chroot's password.sh reads
  [ "$(jq -r '.root_password' "$dir/host-secrets.json")" = "hunter2" ]
  # install-state points the back-end at it via the NO-SOPS key
  [ "$(jq -r '.guided_passwords.host' "$state")" = "$dir/host-secrets.json" ]
  # the SOPS gate (.secrets.*) stays untouched, so no SOPS program is activated
  jq -e '.secrets == null' "$state"
}

# ── per-user secrets carry the keys create-user.sh consumes ─────────────────

@test "guided_write_passwords: per-user secrets land with the create-user.sh keys" {
  state="$TEST_DIR/install-state.json"; echo '{}' > "$state"
  dir="$TEST_DIR/secrets"
  secrets='{"users":{"alice":{"password":"12345",
            "ssh_identity_private_key":"KEYDATA","ssh_identity_key_type":"ed25519"}}}'

  guided_write_passwords "$secrets" "$dir" "$state"

  [ "$(jq -r '.password' "$dir/alice-secrets.json")" = "12345" ]
  [ "$(jq -r '.ssh_identity_private_key' "$dir/alice-secrets.json")" = "KEYDATA" ]
  [ "$(jq -r '.ssh_identity_key_type' "$dir/alice-secrets.json")" = "ed25519" ]
  [ "$(jq -r '.guided_passwords.users.alice' "$state")" \
    = "$dir/alice-secrets.json" ]
}

# ── empty input: no files, the seam object still initialised ────────────────

@test "guided_write_passwords: no root + no users writes no secret files" {
  state="$TEST_DIR/install-state.json"; echo '{}' > "$state"
  dir="$TEST_DIR/secrets"

  guided_write_passwords '{}' "$dir" "$state"

  [ ! -f "$dir/host-secrets.json" ]
  jq -e '.guided_passwords == {}' "$state"
  jq -e '(.guided_passwords.users // {}) == {}' "$state"
}
