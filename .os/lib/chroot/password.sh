#!/usr/bin/env bash
# lib/chroot/password.sh — part of the Chroot Configuration Module
# Runs inside arch-chroot. Applies the FINAL root password from ROOT_PW (never
# written to disk). The precedence — a Host Secret's .root_password over the
# collected/default value — is resolved host-side in configure_system
# (_resolve_root_password), so exactly one value reaches here.
set -Eeuo pipefail
# shellcheck source=./chroot-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/chroot-common.sh"
chroot_err_trap "password"

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

printf '%s:%s\n' "root" "$ROOT_PW" | chpasswd
echo "Root password set."
