#!/usr/bin/env bash
# =============================================================================
# programs/bootloader/grub/install.sh
# =============================================================================
# Invoked by lib/profiles/runner.sh inside arch-chroot, as root, via run-program.sh
# (which sources Shell Stdlib first, providing print_status).
#
# Thin entry point over the shared GRUB installer (lib/grub-common.sh, staged
# to ${SHELL_COMMONS}/grub-common.sh). The same code backs the bootloader
# adapter — see lib/chroot/bootloader-grub.sh.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[grub] error on line $LINENO" >&2' ERR

print_status info "Installing grub + os-prober and writing GRUB config..."
# shellcheck source=../../../lib/grub-common.sh
source "${SHELL_COMMONS}/grub-common.sh"
grub_install_and_configure
print_status success "grub installed and configured."
