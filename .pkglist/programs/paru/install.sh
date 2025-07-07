#!/usr/bin/env bash

set -euo pipefail
trap 'echo "Error on line $LINENO"' ERR

# shellcheck source=/dev/null
source "$SHELL_COMMONS/permissions.sh"
source "$SHELL_COMMONS/strings.sh"

# Create a temporary working directory
TMPDIR=$(mktemp -d)
print_status info "Creating temporary directory to clone paru into: $TMPDIR ..."

chown -R "$SUDO_USER":"$SUDO_USER" "$TMPDIR"

# Clone and build paru as the original user
print_status info "Building and installing paru..."
"$SUDO" -u "$SUDO_USER" bash <<EOF
cd "$TMPDIR"
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si --noconfirm --nocheck --skipinteg
EOF

# Clean up
print_status info "Removing temporary directory: $TMPDIR"
rm -rf "$TMPDIR"

print_status success "Paru installed successfully!"
