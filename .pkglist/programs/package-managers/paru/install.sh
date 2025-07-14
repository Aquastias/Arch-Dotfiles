#!/usr/bin/env bash

set -euo pipefail
trap 'echo "Error on line $LINENO"' ERR

# shellcheck source=/dev/null
source "$SHELL_COMMONS/permissions.sh"
# shellcheck source=/dev/null
source "$SHELL_COMMONS/strings.sh"

# Ask for sudo password upfront and extend timeout
"$SUDO" -v

# Ensure base-devel and git are installed so makepkg won't ask
pacman -Sy --needed --noconfirm base-devel git

TMPDIR=$(mktemp -d)
print_status info "Creating temporary directory to clone paru into: $TMPDIR ..."

chown -R "$SUDO_USER":"$SUDO_USER" "$TMPDIR"

print_status info "Building and installing paru as $SUDO_USER..."
"$SUDO" -u "$SUDO_USER" bash <<EOF
cd "$TMPDIR"
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si --noconfirm --nocheck --skipinteg
EOF

print_status info "Cleaning up temporary directory..."
rm -rf "$TMPDIR"

print_status success "Paru installed successfully!"
