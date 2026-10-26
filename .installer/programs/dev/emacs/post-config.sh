#!/usr/bin/env bash
# =============================================================================
# programs/dev/emacs/post-config.sh
# =============================================================================
# The Post-Config Hook (ADR 0160): invoked by .installer/lib/profiles/runner.sh
# inside arch-chroot as the owning user (no sudo), after the Config Apply pass
# placed the Doom config, with INSTALLER_DIR, PROGRAMS and SHELL_COMMONS
# pre-exported.
#
# Runs Doom's install (which syncs ~200 packages) against the placed config —
# here, not in install.sh, because Doom bakes its config dir's absolute path
# into the profile it generates. No env file: Emacs finds the system servers
# on the default PATH. A failed sync warns, never fails the install: Emacs
# works, and `doom sync` re-runs by hand.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[emacs] error on line $LINENO" >&2' ERR

DOOM_CORE="${HOME}/.config/emacs"
DOOM_CONFIG="${HOME}/.config/doom"

if [[ ! -x "${DOOM_CORE}/bin/doom" ]]; then
  print_status warning "No Doom clone at ${DOOM_CORE}; skipping Doom sync."
elif [[ ! -f "${DOOM_CONFIG}/init.el" ]]; then
  # The user excluded this config (config_exclude): never sync Doom's defaults.
  print_status warning "No Doom config at ${DOOM_CONFIG}; skipping Doom sync."
elif "${DOOM_CORE}/bin/doom" --force install --no-env; then
  print_status success "Doom synced."
else
  print_status warning "Doom sync failed; run ${DOOM_CORE}/bin/doom sync."
fi
