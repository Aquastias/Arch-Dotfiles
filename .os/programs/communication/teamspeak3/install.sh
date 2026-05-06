#!/usr/bin/env bash
# =============================================================================
# programs/communication/teamspeak3/install.sh
# =============================================================================
# Invoked by .os/lib/profiles.sh inside arch-chroot, as the owning user, with
# OS_DIR, PROGRAMS, SHELL_COMMONS pre-exported. Builds and installs the AUR
# `teamspeak3` package via paru, then drops the bundled Material icon pack
# and Demus theme into ~/.ts3client so the user lands on a styled client at
# first launch.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[teamspeak3] error on line $LINENO" >&2' ERR

# shellcheck source=/dev/null
source "${SHELL_COMMONS}/shell-stdlib.sh"

if ! package_installed "teamspeak3"; then
  print_status info "Installing teamspeak3 from AUR..."
  paru -S --noconfirm --skipreview teamspeak3
fi

mkdir -p "${HOME}/.ts3client/gfx" "${HOME}/.ts3client/styles"

ADDONS="${PROGRAMS}/communication/teamspeak3/addons"
cp -R "${ADDONS}/icons/MaterialForTeamspeakWhite" "${HOME}/.ts3client/gfx/"
cp -R "${ADDONS}/themes/Demus/Demus"              "${HOME}/.ts3client/styles/"
cp    "${ADDONS}/themes/Demus/Demus.qss"          "${HOME}/.ts3client/styles/"
cp    "${ADDONS}/themes/Demus/Demus_chat.qss"     "${HOME}/.ts3client/styles/"

print_status success "teamspeak3 installed for $(whoami)."
