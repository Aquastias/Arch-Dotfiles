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
# config runs sandbox.enabled), gh (github-cli), ccusage (statusline usage
# detail), and npm (for the npx skill-store bootstrap below). Its config
# (home/.claude/ — settings.json, CLAUDE.md, scripts/statusline.sh, the latter
# committed +x) is applied by the Runner's Config Apply pass, not here (ADR
# 0134). The Matt Pocock skill store is bootstrapped here via the `skills` CLI —
# a regenerable runtime asset, not tracked config. .credentials.json is never
# written; Claude's /login creates it (0600) on first run.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[claude] error on line $LINENO" >&2' ERR

print_status info "Installing claude-code and companions..."
${AUR_HELPER} -S --noconfirm --needed \
  claude-code bubblewrap socat github-cli ccusage npm

# Skill store: install the Matt Pocock skill set via the Vercel `skills` CLI —
# populates ~/.agents + symlinks into ~/.claude/skills, writing ~/.skill-lock.json
# from current upstream. A regenerable runtime asset (never tracked, like a
# package), so seeding it here keeps install.sh package-only in spirit (ADR 0134).
# Non-fatal: a box that is offline or lacks npx still installs cleanly.
print_status info "Bootstrapping Matt Pocock skill store..."
if command -v npx >/dev/null 2>&1; then
  npx --yes skills@latest add mattpocock/skills \
    || print_status warn "skill-store bootstrap failed; run it manually later."
else
  print_status warn "npx unavailable; skipping skill-store bootstrap."
fi

print_status success "Claude Code installed." \
  "Config applied by the Runner pass; run 'claude' then /login to sign in."
