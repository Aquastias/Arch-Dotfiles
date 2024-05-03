#!/usr/bin/env bash

function package_installed() {
  pacman -Q "$1" &>/dev/null
}

echo "Installing teamspeak3..."

if ! command -v paru &>/dev/null; then
  echo "paru is not installed!"
  exit 127
fi

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

cp -R "$HOME/.dotfiles/.pkglist/teamspeak3/addons/icons/MaterialForTeamspeakWhite" "$HOME/.ts3client/gfx"
cp -R "$HOME/.dotfiles/.pkglist/teamspeak3/addons/themes/Demus/Demus" "$HOME/.ts3client/styles"
cp -R "$HOME/.dotfiles/.pkglist/teamspeak3/addons/themes/Demus/Demus.qss" "$HOME/.ts3client/styles"
cp -R "$HOME/.dotfiles/.pkglist/teamspeak3/addons/themes/Demus/Demus_chat.qss" "$HOME/.ts3client/styles"

echo "Installation finished!"
