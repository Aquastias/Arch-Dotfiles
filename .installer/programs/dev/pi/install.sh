#!/usr/bin/env bash
# =============================================================================
# programs/dev/pi/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as the owning
# user (the runner grants temp NOPASSWD sudo — unused here; paru + $HOME writes
# only), with INSTALLER_DIR/PROGRAMS/SHELL_COMMONS/AUR_HELPER pre-exported.
#
# Installs the pi coding agent (pi-coding-agent-bin, AUR) and seeds ~/.pi/agent/
# from the payload bundled beside this script (settings.json, web-search.json,
# mcp.json, themes/ — the same config the repo-root .pi/ stow tree carries).
# Seeds only — the operator stows the repo copy by hand (ADR 0095/0127).
# auth.json is never written here; pi's `/login` creates it (0600) on first run.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[pi] error on line $LINENO" >&2' ERR

print_status info "Installing pi-coding-agent-bin..."
${AUR_HELPER} -S --noconfirm --needed pi-coding-agent-bin

mkdir -p "${HOME}/.pi/agent"
cp -r "${PROGRAMS}/dev/pi/agent/." "${HOME}/.pi/agent/"
print_status info "Seeded ~/.pi/agent (settings, web-search, mcp, theme)."

print_status success "Pi staged." \
  "Run 'pi' then /login to sign in to Claude; config is hand-stowable."
