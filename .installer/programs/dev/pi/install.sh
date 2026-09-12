#!/usr/bin/env bash
# =============================================================================
# programs/dev/pi/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as the owning
# user with temp NOPASSWD sudo, with INSTALLER_DIR, PROGRAMS, SHELL_COMMONS and
# AUR_HELPER pre-exported.
#
# Installs the pi coding agent (pi-coding-agent-bin, AUR) and seeds
# ~/.pi/agent/settings.json from the payload bundled beside this script (the
# same config the repo-root .pi/ stow tree carries). Seeds only — the operator
# stows the repo copy by hand (ADR 0095/0127). auth.json is never written here;
# pi's `/login` creates it (0600) on first run.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[pi] error on line $LINENO" >&2' ERR

print_status info "Installing pi-coding-agent-bin..."
${AUR_HELPER} -S --noconfirm --needed pi-coding-agent-bin

mkdir -p "${HOME}/.pi/agent"
cp "${PROGRAMS}/dev/pi/agent/settings.json" "${HOME}/.pi/agent/settings.json"
print_status info "Seeded ~/.pi/agent/settings.json."

print_status success "Pi staged." \
  "Run 'pi' then /login to sign in to Claude; config is hand-stowable."
