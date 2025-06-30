#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$SHELL_COMMONS/permissions.sh"

check_root

TMP_DIR=$(mktemp -d)
echo "📁 Cloning paru into temporary directory: $TMP_DIR"

git clone https://aur.archlinux.org/paru.git "$TMP_DIR/paru"

cd "$TMP_DIR/paru" || exit
echo "🔧 Building and installing paru..."
makepkg -si --noconfirm

echo "🧹 Cleaning up temporary directory..."
rm -rf "$TMP_DIR"

echo "✅ Paru installed successfully."
