#!/usr/bin/env bash
# lib/chroot/password.sh — part of the Chroot Configuration Module
# Runs inside arch-chroot. Applies the FINAL root password from ROOT_PW (never
# written to disk). The precedence — a Host Secret's .root_password over the
# collected/default value — is resolved host-side in configure_system
# (_resolve_root_password), so exactly one value reaches here. Also applies the
# root login shell from ROOT_SHELL (install-state options.root_shell, ADR 0054).
set -Eeuo pipefail
# shellcheck source=./chroot-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/chroot-common.sh"
chroot_err_trap "password"

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

printf '%s:%s\n' "root" "$ROOT_PW" | chpasswd
echo "Root password set."

# Root login shell (ADR 0054): install-state carries options.root_shell as
# ROOT_SHELL (default /bin/bash). Install the shell's package if absent — the
# same guard create-user.sh uses — so a zsh/fish root can never break login.
ROOT_SHELL="${ROOT_SHELL:-/bin/bash}"
ensure_login_shell_installed "$ROOT_SHELL"
chsh -s "$ROOT_SHELL" root
echo "Root shell set to ${ROOT_SHELL}."
