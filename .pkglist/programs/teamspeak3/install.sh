#!/usr/bin/env bash

set -euo pipefail
trap 'echo "Error on line $LINENO"' ERR

# shellcheck source=/dev/null
source "$SHELL_COMMONS/commands.sh"
source "$SHELL_COMMONS/packages.sh"
source "$SHELL_COMMONS/permissions.sh"
source "$SHELL_COMMONS/strings.sh"

check_root
check_command "paru"

print_status info "Installing TeamSpeak3..."

if ! package_installed "teamspeak3"; then
  paru -S --noconfirm --skipreview teamspeak3
fi

if [ ! -d "$HOME/.ts3client" ]; then
  mkdir "$HOME/.ts3client"
fi

if [ ! -d "$HOME/.ts3client/gfx" ]; then
  mkdir "$HOME/.ts3client/gfx"
fi

if [ ! -d "$HOME/.ts3client/styles" ]; then
  mkdir "$HOME/.ts3client/styles"
fi

cp -R "$DOTFILES/.pkglist/teamspeak3/addons/icons/MaterialForTeamspeakWhite" "$HOME/.ts3client/gfx"
cp -R "$DOTFILES/.pkglist/teamspeak3/addons/themes/Demus/Demus" "$HOME/.ts3client/styles"
cp -R "$DOTFILES/.pkglist/teamspeak3/addons/themes/Demus/Demus.qss" "$HOME/.ts3client/styles"
cp -R "$DOTFILES/.pkglist/teamspeak3/addons/themes/Demus/Demus_chat.qss" "$HOME/.ts3client/styles"

print_status success "Installation finished!"
