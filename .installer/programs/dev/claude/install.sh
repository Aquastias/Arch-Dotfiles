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
# detail). Seeds ~/.claude/ from the payload bundled beside this script
# (settings.json, CLAUDE.md, scripts/statusline.sh — the same config the repo
# .claude/ stow tree carries). Seeds only — the operator stows the repo copy by
# hand (ADR 0095/0133). .credentials.json is never written here; Claude's
# /login creates it (0600) on first run.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[claude] error on line $LINENO" >&2' ERR

print_status info "Installing claude-code and companions..."
${AUR_HELPER} -S --noconfirm --needed \
  claude-code bubblewrap socat github-cli ccusage

mkdir -p "${HOME}/.claude"
cp -r "${PROGRAMS}/dev/claude/payload/." "${HOME}/.claude/"
chmod +x "${HOME}/.claude/scripts/statusline.sh"
print_status info "Seeded ~/.claude (settings, CLAUDE.md, statusline)."

print_status success "Claude Code staged." \
  "Run 'claude' then /login to sign in; config is hand-stowable."
