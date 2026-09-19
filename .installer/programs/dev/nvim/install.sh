#!/usr/bin/env bash
# =============================================================================
# programs/dev/nvim/install.sh
# =============================================================================
# Sourced by .installer/lib/profiles/runner.sh inside arch-chroot as the owning
# user, with INSTALLER_DIR/PROGRAMS/SHELL_COMMONS/AUR_HELPER pre-exported.
#
# The Neovim config (home/) is applied by the Runner's Config Apply pass, not
# here (ADR 0134). The LSP/formatter toolchain is declared in Host Core
# language-servers as bare packages (editor-agnostic, no mason — ADR 0135), so
# the base install already places it. This program only stages the config and
# installs the ONE best-effort exception: Swift's sourcekit-lsp, which ships
# with the AUR swift-bin toolchain (AUR-only, heavy). It is attempted but never
# fails the install — a missing Swift is an optional gap, not a broken editor
# (ADR 0135/0136).
# =============================================================================

set -Eeuo pipefail
trap 'echo "[nvim] error on line $LINENO" >&2' ERR

print_status info "Installing Swift toolchain (sourcekit-lsp) — best-effort..."
if ${AUR_HELPER} -S --noconfirm --needed swift-bin; then
  print_status success "Swift toolchain installed (sourcekit-lsp available)."
else
  print_status warning "Swift unavailable; sourcekit-lsp skipped (optional)."
fi

print_status success "Neovim staged." \
  "Config applied by the Runner pass; LSP toolchain from Host Core."
