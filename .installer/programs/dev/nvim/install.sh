#!/usr/bin/env bash
# =============================================================================
# programs/dev/nvim/install.sh
# =============================================================================
# Sourced by .installer/lib/profiles/runner.sh inside arch-chroot as the owning
# user, with INSTALLER_DIR/PROGRAMS/SHELL_COMMONS/AUR_HELPER pre-exported.
#
# The Neovim config (home/) is applied by the Runner's Config Apply pass, not
# here (ADR 0134): install.sh installs packages only. The neovim binary is
# core-owned (Host Core packages.editors); this program installs the editor
# toolchain — LSP servers, formatters, linters — as system packages, no mason
# (ADR 0135). The toolchain set lands in later tickets; this tracer bullet
# installs nothing beyond core and lets the Config Apply pass place the config.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[nvim] error on line $LINENO" >&2' ERR

print_status info "Neovim config staged; toolchain packages install later."

print_status success "Neovim staged." \
  "Config applied by the Runner pass; static Catppuccin Mocha Sapphire default."
