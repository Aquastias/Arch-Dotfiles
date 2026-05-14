#!/usr/bin/env bash
set -Eeuo pipefail

AGE_KEY=/etc/secrets/age/keys.txt
SOPS_SECRETS_DIR=/etc/secrets/sops
RUN_SECRETS=/run/secrets

if [[ ! -f "$AGE_KEY" ]]; then
  echo "[sops-runtime] no age key at $AGE_KEY — skipping" >&2
  exit 0
fi

mkdir -p "$RUN_SECRETS"
mount -t tmpfs -o size=10m,mode=0700 tmpfs "$RUN_SECRETS"

export SOPS_AGE_KEY_FILE="$AGE_KEY"

shopt -s nullglob
for f in "${SOPS_SECRETS_DIR}"/*.json; do
  name="$(basename "$f" .json)"
  sops --decrypt "$f" > "${RUN_SECRETS}/${name}.json"
  chmod 600 "${RUN_SECRETS}/${name}.json"
done
