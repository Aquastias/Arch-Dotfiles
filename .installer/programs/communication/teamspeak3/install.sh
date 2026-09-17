#!/usr/bin/env bash
# =============================================================================
# programs/communication/teamspeak3/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as the owning
# user, with INSTALLER_DIR, PROGRAMS, SHELL_COMMONS pre-exported. Builds and
# installs the AUR `teamspeak3` package via paru. The Material icon pack + Demus
# theme (home/.ts3client/) are applied by the Runner's Config Apply pass, not
# here (ADR 0134): install.sh installs the package only, so the user lands on a
# styled client without this script touching $HOME.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[teamspeak3] error on line $LINENO" >&2' ERR

if ! package_installed "teamspeak3"; then
  print_status info "Installing teamspeak3 from AUR..."
  ${AUR_HELPER} -S --noconfirm teamspeak3
fi

print_status success "teamspeak3 installed for $(whoami)." \
  "Config (icons + theme) applied by the Runner pass."
