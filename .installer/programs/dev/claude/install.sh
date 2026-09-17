#!/usr/bin/env bash
# =============================================================================
# programs/dev/claude/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as the owning
# user (the runner grants temp NOPASSWD sudo — unused here; paru + $HOME writes
# only), with INSTALLER_DIR/PROGRAMS/SHELL_COMMONS/AUR_HELPER pre-exported.
#
# Installs Claude Code (claude-code, AUR) plus its Bash-sandbox runtime
# (bubblewrap + socat — optdepends upstream, mandatory here because the seeded
# config runs sandbox.enabled), gh (github-cli), and ccusage (statusline usage
# detail). Its config (home/.claude/ — settings.json, CLAUDE.md,
# scripts/statusline.sh, the latter committed +x) is applied by the Runner's
# Config Apply pass, not here (ADR 0134): install.sh installs the packages only.
# .credentials.json is never written; Claude's /login creates it (0600) on
# first run.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[claude] error on line $LINENO" >&2' ERR

print_status info "Installing claude-code and companions..."
${AUR_HELPER} -S --noconfirm --needed \
  claude-code bubblewrap socat github-cli ccusage

print_status success "Claude Code installed." \
  "Config applied by the Runner pass; run 'claude' then /login to sign in."
