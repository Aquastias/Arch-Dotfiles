#!/usr/bin/env bats
# Tests for .os/vm/fixtures/regenerate.sh — Test Age Key rotation script.
#
# Runs regenerate.sh against an isolated REPO_ROOT temp workspace so the
# committed fixtures under .os/vm/fixtures, .os/hosts/vm/arch-secure and
# .os/users/vm-test are never mutated.

REGEN="$BATS_TEST_DIRNAME/../../vm/fixtures/regenerate.sh"
PASSPHRASE="test"

setup() {
  TEST_DIR="$(mktemp -d)"
  export REPO_ROOT="$TEST_DIR"
  mkdir -p \
    "$TEST_DIR/.os/vm/fixtures" \
    "$TEST_DIR/.os/hosts/vm/arch-secure" \
    "$TEST_DIR/.os/users/vm-test"

  # .sops.yaml with the test rule placed before the operator placeholder so
  # the test paths win their match. regenerate.sh updates the test rule's age.
  cat > "$TEST_DIR/.sops.yaml" <<'YAML'
creation_rules:
  - path_regex: ^\.os/(hosts/vm/arch-secure|users/vm-test)/secrets\.json$
    age: >-
      age1placeholderplaceholderplaceholderplaceholderplaceholder
  - path_regex: (users|hosts)/[^/]+/secrets\.json$
    age: >-
      age1REPLACE_WITH_OPERATOR_PUBLIC_KEY
YAML

  # Plaintext seed secrets. regenerate.sh detects unencrypted JSON and runs
  # sops -e -i on first run; subsequent runs hit the sops updatekeys path.
  printf '{"root_password":"vmtest"}\n' \
    > "$TEST_DIR/.os/hosts/vm/arch-secure/secrets.json"
  printf '{"password":"vmtest","ssh_identity_key_type":"ed25519"}\n' \
    > "$TEST_DIR/.os/users/vm-test/secrets.json"
}

teardown() { rm -rf "$TEST_DIR"; }

# Decrypt a passphrase-encrypted age file non-interactively via a pty.
_decrypt_key_age() {
  local path="$1"
  script -qc "age -d '$path'" /dev/null <<< "${PASSPHRASE}"$'\n' \
    | sed -n 's/\r$//; /AGE-SECRET-KEY-1/p'
}

_sops_yaml_test_recipient() {
  python3 -c '
import sys, yaml
data = yaml.safe_load(open(sys.argv[1]))
for r in data["creation_rules"]:
    if "arch-secure" in r["path_regex"]:
        print(r["age"].strip()); break
' "$1"
}

# Decrypt a SOPS file using a freshly-decrypted Test Age private key.
# Stdout: plaintext JSON; exit 0 on success.
_sops_decrypt_with_test_key() {
  local sops_file="$1"
  local key_file="$TEST_DIR/.os/vm/fixtures/key.age"
  local priv="$TMP_SOPS/key.txt"
  mkdir -p "$TMP_SOPS"
  _decrypt_key_age "$key_file" > "$priv"
  SOPS_AGE_KEY_FILE="$priv" sops -d "$sops_file"
}

setup_file() { :; }

# ── tracer bullet ─────────────────────────────────────────────────────────────

@test "regenerate.sh writes key.age that decrypts with passphrase 'test'" {
  run bash "$REGEN"
  [ "$status" -eq 0 ]
  [ -s "$TEST_DIR/.os/vm/fixtures/key.age" ]

  local priv
  priv="$(_decrypt_key_age "$TEST_DIR/.os/vm/fixtures/key.age")"
  [[ "$priv" == AGE-SECRET-KEY-1* ]]
}

@test "regenerate.sh writes the new public key into .sops.yaml test rule" {
  bash "$REGEN"

  local priv pub_from_key pub_in_yaml
  priv="$(_decrypt_key_age "$TEST_DIR/.os/vm/fixtures/key.age")"
  pub_from_key="$(printf '%s\n' "$priv" | age-keygen -y 2>/dev/null)"
  pub_in_yaml="$(_sops_yaml_test_recipient "$TEST_DIR/.sops.yaml")"

  [ -n "$pub_from_key" ]
  [ "$pub_from_key" = "$pub_in_yaml" ]
}

@test "regenerate.sh encrypts both seed secrets.json files round-trippably" {
  TMP_SOPS="$(mktemp -d)"
  bash "$REGEN"

  local host_dec user_dec
  host_dec="$(_sops_decrypt_with_test_key \
    "$TEST_DIR/.os/hosts/vm/arch-secure/secrets.json")"
  user_dec="$(_sops_decrypt_with_test_key \
    "$TEST_DIR/.os/users/vm-test/secrets.json")"

  [[ "$host_dec" == *root_password* ]]
  [[ "$user_dec" == *ssh_identity_key_type* ]]

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

  local host_dec user_dec
  host_dec="$(_sops_decrypt_with_test_key \
    "$TEST_DIR/.os/hosts/vm/arch-secure/secrets.json")"
  user_dec="$(_sops_decrypt_with_test_key \
    "$TEST_DIR/.os/users/vm-test/secrets.json")"
  [[ "$host_dec" == *root_password* ]]
  [[ "$user_dec" == *ssh_identity_key_type* ]]

  rm -rf "$TMP_SOPS"
}
