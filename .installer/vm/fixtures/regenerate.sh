#!/usr/bin/env bash
# =============================================================================
# .os/vm/fixtures/regenerate.sh — rotate the Test Age Key.
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${REPO_ROOT:=$(cd "$SCRIPT_DIR/../../.." && pwd)}"

PASSPHRASE="test"
KEY_AGE="$REPO_ROOT/.os/vm/fixtures/key.age"
SOPS_YAML="$REPO_ROOT/.sops.yaml"
SECRETS_FILES=(
  "$REPO_ROOT/.os/hosts/vm/arch-secure/secrets.json"
  "$REPO_ROOT/.os/users/vm-test/secrets.json"
)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 0. If a prior key.age exists, decrypt it now — sops updatekeys will need
#    this private key to read existing encrypted secrets.
OLD_KEY=""
if [[ -s "$KEY_AGE" ]]; then
  OLD_KEY="$TMP/old.txt"
  script -qc "age -d -o '$OLD_KEY' '$KEY_AGE'" /dev/null \
    <<< "${PASSPHRASE}"$'\n' >/dev/null || OLD_KEY=""
  [[ -s "$OLD_KEY" ]] || OLD_KEY=""
fi

# 1. New keypair.
age-keygen -o "$TMP/new.txt" 2>/dev/null
PUB="$(age-keygen -y "$TMP/new.txt")"

# 2. Passphrase-encrypt private key to key.age. age requires a tty for the
#    passphrase prompt, so allocate a pty via util-linux `script`.
mkdir -p "$(dirname "$KEY_AGE")"
script -qc "age -p -o '$KEY_AGE' '$TMP/new.txt'" /dev/null \
  <<< "${PASSPHRASE}"$'\n'"${PASSPHRASE}"$'\n' >/dev/null

# 3. Update the test rule's age recipient in .sops.yaml. Targeted text edit
#    preserves the operator placeholder rule byte-for-byte.
python3 - "$SOPS_YAML" "$PUB" <<'PY'
import re, sys
path, pub = sys.argv[1], sys.argv[2]
text = open(path).read()
new = re.sub(
    r'(path_regex:[^\n]*arch-secure[^\n]*\n\s*age:\s*>-\n\s*)age1[a-z0-9]+',
    r'\g<1>' + pub,
    text, count=1)
if new == text:
    sys.exit("regenerate.sh: failed to locate test rule in " + path)
open(path, 'w').write(new)
PY

# 4. Re-key (or encrypt-fresh) every committed secrets.json. sops walks
#    upward to find .sops.yaml, so cd into REPO_ROOT first. updatekeys uses
#    the old private key to decrypt the existing file, then re-encrypts to
#    the recipient now in .sops.yaml.
cd "$REPO_ROOT"
KEY_FILE_FOR_DECRYPT="${OLD_KEY:-$TMP/new.txt}"
for sf in "${SECRETS_FILES[@]}"; do
  [[ -f "$sf" ]] || { echo "regenerate.sh: missing $sf" >&2; exit 1; }
  if grep -q '"sops"' "$sf"; then
    SOPS_AGE_KEY_FILE="$KEY_FILE_FOR_DECRYPT" \
      sops updatekeys --yes "$sf" >/dev/null
  else
    sops -e -i "$sf"
  fi
done
