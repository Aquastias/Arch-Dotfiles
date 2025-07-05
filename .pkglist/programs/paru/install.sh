#!/usr/bin/env bash

set -e

# shellcheck source=/dev/null
source "$SHELL_COMMONS/permissions.sh"

# Create a temporary working directory
TMPDIR=$(mktemp -d)
echo "📁 Creating temporary directory to clone paru into: $TMPDIR"
chown -R "$SUDO_USER":"$SUDO_USER" "$TMPDIR"

# Clone and build paru as the original user
echo "🔧 Building and installing paru..."
"$SUDO" -u "$SUDO_USER" bash <<EOF
cd "$TMPDIR"
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si --noconfirm --nocheck --skipinteg
EOF

# Clean up
echo "📁 Removing temporary directory: $TMPDIR"
rm -rf "$TMPDIR"

echo "✅ Paru installed successfully."
