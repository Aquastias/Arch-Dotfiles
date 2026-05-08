#!/usr/bin/env bash
# lib/chroot/password.sh — part of the Chroot Configuration Module
# Runs inside arch-chroot. Reads ROOT_PW from env (never written to disk).
set -Eeuo pipefail
trap 'echo "[chroot:password] failed at line $LINENO" >&2' ERR

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
printf '%s:%s\n' "root" "$ROOT_PW" | chpasswd
echo "Root password set."
