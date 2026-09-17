#!/usr/bin/env bash
# =============================================================================
# programs/system/yazi/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as the owning
# user (the runner grants temp NOPASSWD sudo, used here for seeding /etc/skel
# and /root), with INSTALLER_DIR/PROGRAMS/SHELL_COMMONS/AUR_HELPER pre-exported.
#
# Installs yazi. Its theme (home/) is applied by the Runner's Config Apply pass,
# not here (ADR 0134): install.sh installs the package only. The theme is static
# ANSI-16 (ADR 0132), following the terminal palette. The program owns the yazi
# package (exclusivity, ADR 0115), so yazi left core packages.shell for here.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[yazi] error on line $LINENO" >&2' ERR

# ── package ──────────────────────────────────────────────────────────────────
print_status info "Installing yazi..."
${AUR_HELPER} -S --noconfirm --needed yazi

print_status success "Yazi installed (ANSI-16 theme)." \
  "Config applied by the Runner pass; follows the terminal palette."
