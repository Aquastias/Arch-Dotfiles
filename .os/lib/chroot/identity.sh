#!/usr/bin/env bash
# lib/chroot/identity.sh — Chroot Configuration Module: system identity
# Runs inside arch-chroot. Reads install-state.json via load-state.sh.
set -Eeuo pipefail
trap 'echo "[chroot:identity] failed at line $LINENO" >&2' ERR

# shellcheck source=./load-state.sh
source "$(dirname "${BASH_SOURCE[0]}")/load-state.sh"

# ── Timezone ──────────────────────────────────────────────────────────────────
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
echo "Timezone set: $TIMEZONE"

# ── Locale ────────────────────────────────────────────────────────────────────
if grep -q "^#${LOCALE} UTF-8" /etc/locale.gen; then
    sed -i "s/^#${LOCALE} UTF-8/${LOCALE} UTF-8/" /etc/locale.gen
else
    echo "${LOCALE} UTF-8" >> /etc/locale.gen
fi
locale-gen
echo "LANG=${LOCALE}"   > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# ── Hostname & /etc/hosts ─────────────────────────────────────────────────────
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF
echo "Identity set: hostname=${HOSTNAME} locale=${LOCALE} tz=${TIMEZONE}"
