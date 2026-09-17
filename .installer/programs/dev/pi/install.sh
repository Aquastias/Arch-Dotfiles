#!/usr/bin/env bash
# =============================================================================
# programs/dev/pi/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as the owning
# user (the runner grants temp NOPASSWD sudo — unused here; paru + $HOME writes
# only), with INSTALLER_DIR/PROGRAMS/SHELL_COMMONS/AUR_HELPER pre-exported.
#
# Installs the pi coding agent (pi-coding-agent-bin, AUR). Its config
# (home/.pi/agent/ — settings.json, web-search.json, mcp.json, themes/) is
# applied by the Runner's Config Apply pass, not here (ADR 0134): install.sh
# installs the package only. auth.json is never written; pi's `/login` creates
# it (0600) on first run.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[pi] error on line $LINENO" >&2' ERR

print_status info "Installing pi-coding-agent-bin..."
${AUR_HELPER} -S --noconfirm --needed pi-coding-agent-bin

print_status success "Pi installed." \
  "Config applied by the Runner pass; run 'pi' then /login to sign in."
