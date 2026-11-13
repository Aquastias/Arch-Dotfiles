#!/usr/bin/env bash
# =============================================================================
# .installer/vm/fixtures/regenerate.sh — rotate the Test Age Key.
# =============================================================================
# Generates a fresh Age keypair, passphrase-encrypts the private key into
# key.age (passphrase "test"), updates the test-rule recipient in .sops.yaml,
# and re-keys the committed secrets.json fixtures so they decrypt with the
# new key. Bootstrap-safe: plaintext secrets.json files are encrypted in
# place on first run; subsequent runs decrypt with the old key, re-encrypt
# to the new recipient via `sops updatekeys`.
#
# Override REPO_ROOT to operate against a temp workspace (used by the bats
# test). Defaults to the repo root inferred from this script's location.
# =============================================================================

set -Eeuo pipefail

script_path="${BASH_SOURCE[0]}"
[[ "$script_path" == */* ]] || script_path="./$script_path"
SCRIPT_DIR="$(cd "${script_path%/*}" && pwd)"
: "${REPO_ROOT:=$(cd "$SCRIPT_DIR/../../.." && pwd)}"

PASSPHRASE="test"
KEY_AGE="$REPO_ROOT/.installer/vm/fixtures/key.age"
SOPS_YAML="$REPO_ROOT/.sops.yaml"
# Every VM fixture secrets.json — all keyed to the Test Age Key by the
# .sops.yaml `(hosts|users)/vm/` rule.
shopt -s nullglob
SECRETS_FILES=(
  "$REPO_ROOT"/.installer/hosts/vm/*/secrets.json
  "$REPO_ROOT"/.installer/users/vm/*/secrets.json
)
shopt -u nullglob
[[ ${#SECRETS_FILES[@]} -gt 0 ]] \
  || { echo "regenerate.sh: no VM secrets.json fixtures found" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 0. If a prior key.age exists, decrypt it now — sops updatekeys will need
#    this private key to read existing encrypted secrets.
OLD_KEY=""
if [[ -s "$KEY_AGE" ]]; then
  OLD_KEY="$TMP/old.txt"
  # script reads age's answers from a regular file (a pipe makes it hang).
  printf '%s\n' "$PASSPHRASE" > "$TMP/answer"
  script -qc "age -d -o '$OLD_KEY' '$KEY_AGE'" /dev/null \
    < "$TMP/answer" >/dev/null || OLD_KEY=""
  [[ -s "$OLD_KEY" ]] || OLD_KEY=""
fi

# 1. New keypair.
age-keygen -o "$TMP/new.txt" 2>/dev/null
PUB="$(age-keygen -y "$TMP/new.txt")"

# 2. Passphrase-encrypt private key to key.age. age requires a tty for the
#    passphrase prompt, so allocate a pty via util-linux `script`.
mkdir -p "$(dirname "$KEY_AGE")"
# The passphrase twice: age asks for it and its confirmation.
printf '%s\n%s\n' "$PASSPHRASE" "$PASSPHRASE" > "$TMP/answers"
script -qc "age -p -o '$KEY_AGE' '$TMP/new.txt'" /dev/null \
  < "$TMP/answers" >/dev/null

# 3. Update the test rule's age recipient in .sops.yaml. Targeted awk edit
#    (no python, repo policy): rewrite only the `age1…` line that follows the
#    VM-fixture (`/vm/`) `path_regex` block; the operator placeholder rule is
#    preserved byte-for-byte. Non-zero when the test rule can't be found.
awk -v pub="$PUB" -f "$(dirname "$0")/sops-recipient.awk" \
  "$SOPS_YAML" > "$SOPS_YAML.tmp" \
  || { echo "regenerate.sh: failed to locate test rule in $SOPS_YAML" >&2
       rm -f "$SOPS_YAML.tmp"; exit 1; }
mv "$SOPS_YAML.tmp" "$SOPS_YAML"

# 4. Re-key (or encrypt-fresh) every committed secrets.json. sops walks
#    upward to find .sops.yaml, so cd into REPO_ROOT first. updatekeys uses
#    the old private key to decrypt the existing file, then re-encrypts to
#    the recipient now in .sops.yaml.
cd "$REPO_ROOT"
KEY_FILE_FOR_DECRYPT="${OLD_KEY:-$TMP/new.txt}"
for secrets_file in "${SECRETS_FILES[@]}"; do
  [[ -f "$secrets_file" ]] \
    || { echo "regenerate.sh: missing $secrets_file" >&2; exit 1; }
  if grep -q '"sops"' "$secrets_file"; then
    SOPS_AGE_KEY_FILE="$KEY_FILE_FOR_DECRYPT" \
      sops updatekeys --yes "$secrets_file" >/dev/null
  else
    sops -e -i "$secrets_file"
  fi
done
