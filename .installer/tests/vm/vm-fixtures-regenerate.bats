#!/usr/bin/env bats
# Tests for .installer/vm/fixtures/regenerate.sh — Test Age Key rotation script.
#
# Runs regenerate.sh against an isolated REPO_ROOT temp workspace so the
# committed fixtures under .installer/vm/fixtures,
# .installer/hosts/vm/arch-secure and
# .installer/users/vm/test are never mutated.

REGEN="$BATS_TEST_DIRNAME/../../vm/fixtures/regenerate.sh"
PASSPHRASE="test"

setup() {
  TEST_DIR="$(mktemp -d)"
  export REPO_ROOT="$TEST_DIR"
  mkdir -p \
    "$TEST_DIR/.installer/vm/fixtures" \
    "$TEST_DIR/.installer/hosts/vm/arch-secure" \
    "$TEST_DIR/.installer/users/vm/test"

  # .sops.yaml with the test rule placed before the operator placeholder so
  # the test paths win their match. regenerate.sh updates the test rule's age.
  cat > "$TEST_DIR/.sops.yaml" <<'YAML'
creation_rules:
  - path_regex: ^\.installer/(hosts|users)/vm/[^/]+/secrets\.json$
    age: >-
      age1placeholderplaceholderplaceholderplaceholderplaceholder
  - path_regex: (users|hosts)/[^/]+/secrets\.json$
    age: >-
      age1REPLACE_WITH_OPERATOR_PUBLIC_KEY
YAML

  # Plaintext seed secrets. regenerate.sh detects unencrypted JSON and runs
  # sops -e -i on first run; subsequent runs hit the sops updatekeys path.
  printf '{"root_password":"vmtest"}\n' \
    > "$TEST_DIR/.installer/hosts/vm/arch-secure/secrets.json"
  printf '{"password":"vmtest","ssh_identity_key_type":"ed25519"}\n' \
    > "$TEST_DIR/.installer/users/vm/test/secrets.json"
}

teardown() { rm -rf "$TEST_DIR"; }

# Decrypt a passphrase-encrypted age file non-interactively via a pty.
_decrypt_key_age() {
  local path="$1"
  script -qc "age -d '$path'" /dev/null <<< "${PASSPHRASE}"$'\n' \
    | awk '{ sub(/\r$/, "") } /AGE-SECRET-KEY-1/'
}

# The VM-fixture rule's age recipient (no python): the age1… line after the
# `/vm/` path_regex block.
_sops_yaml_test_recipient() {
  awk '
    /path_regex:.*\/vm\// { found = 1; next }
    found && /^[[:space:]]*age1[a-z0-9]+[[:space:]]*$/ {
      gsub(/[[:space:]]/, ""); print; exit
    }
  ' "$1"
}

# Decrypt a SOPS file using a freshly-decrypted Test Age private key.
# Stdout: plaintext JSON; exit 0 on success.
_sops_decrypt_with_test_key() {
  local sops_file="$1"
  local key_file="$TEST_DIR/.installer/vm/fixtures/key.age"
  local private_key="$TMP_SOPS/key.txt"
  mkdir -p "$TMP_SOPS"
  _decrypt_key_age "$key_file" > "$private_key"
  SOPS_AGE_KEY_FILE="$private_key" sops -d "$sops_file"
}

setup_file() { :; }

# ── tracer bullet ─────────────────────────────────────────────────────────────

@test "regenerate.sh writes key.age that decrypts with passphrase 'test'" {
  run bash "$REGEN"
  [ "$status" -eq 0 ]
  [ -s "$TEST_DIR/.installer/vm/fixtures/key.age" ]

  local private_key
  private_key="$(_decrypt_key_age "$TEST_DIR/.installer/vm/fixtures/key.age")"
  [[ "$private_key" == AGE-SECRET-KEY-1* ]]
}

@test "regenerate.sh writes the new public key into .sops.yaml test rule" {
  bash "$REGEN"

  local private_key public_from_key public_in_yaml
  private_key="$(_decrypt_key_age "$TEST_DIR/.installer/vm/fixtures/key.age")"
  public_from_key="$(printf '%s\n' "$private_key" | age-keygen -y 2>/dev/null)"
  public_in_yaml="$(_sops_yaml_test_recipient "$TEST_DIR/.sops.yaml")"

  [ -n "$public_from_key" ]
  [ "$public_from_key" = "$public_in_yaml" ]
}

@test "regenerate.sh encrypts both seed secrets.json files round-trippably" {
  TMP_SOPS="$(mktemp -d)"
  bash "$REGEN"

  local host_decrypted user_decrypted
  host_decrypted="$(_sops_decrypt_with_test_key \
    "$TEST_DIR/.installer/hosts/vm/arch-secure/secrets.json")"
  user_decrypted="$(_sops_decrypt_with_test_key \
    "$TEST_DIR/.installer/users/vm/test/secrets.json")"

  [[ "$host_decrypted" == *root_password* ]]
  [[ "$user_decrypted" == *ssh_identity_key_type* ]]

  rm -rf "$TMP_SOPS"
}

@test "regenerate.sh is idempotent: 2nd run rotates key, secrets still decrypt" {
  TMP_SOPS="$(mktemp -d)"
  bash "$REGEN"
  local pub1
  pub1="$(_sops_yaml_test_recipient "$TEST_DIR/.sops.yaml")"

  bash "$REGEN"
  local pub2
  pub2="$(_sops_yaml_test_recipient "$TEST_DIR/.sops.yaml")"

  [ "$pub1" != "$pub2" ]

  local host_decrypted user_decrypted
  host_decrypted="$(_sops_decrypt_with_test_key \
    "$TEST_DIR/.installer/hosts/vm/arch-secure/secrets.json")"
  user_decrypted="$(_sops_decrypt_with_test_key \
    "$TEST_DIR/.installer/users/vm/test/secrets.json")"
  [[ "$host_decrypted" == *root_password* ]]
  [[ "$user_decrypted" == *ssh_identity_key_type* ]]

  rm -rf "$TMP_SOPS"
}

@test "regenerate.sh re-keys every hosts/vm/*/secrets.json fixture" {
  TMP_SOPS="$(mktemp -d)"
  local extra="$TEST_DIR/.installer/hosts/vm/arch-extra/secrets.json"
  mkdir -p "${extra%/*}"
  printf '{"root_password":"vmtest"}\n' > "$extra"

  bash "$REGEN"

  local decrypted
  decrypted="$(_sops_decrypt_with_test_key "$extra")"
  [[ "$decrypted" == *root_password* ]]

  rm -rf "$TMP_SOPS"
}
