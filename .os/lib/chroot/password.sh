#!/usr/bin/env bash
# lib/chroot/password.sh — part of the Chroot Configuration Module
# Runs inside arch-chroot. Reads ROOT_PW from env (never written to disk).
set -Eeuo pipefail
trap 'echo "[chroot:password] failed at line $LINENO" >&2' ERR

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

if [[ -n "${HOST_SECRETS_FILE:-}" && -f "$HOST_SECRETS_FILE" ]]; then
  sec_pw="$(jq -r '.root_password // empty' "$HOST_SECRETS_FILE")"
  [[ -n "$sec_pw" ]] && ROOT_PW="$sec_pw"
fi

printf '%s:%s\n' "root" "$ROOT_PW" | chpasswd
echo "Root password set."
