#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$SHELL_COMMONS/commands.sh"
source "$SHELL_COMMONS/packages.sh"

check_command "paru"

echo "Installing teamspeak3..."

if ! package_installed "whoogle"; then
  eval "$SUDO paru -S --skipreview --noconfirm whoogle"
fi

sleep 5

eval "$SUDO chown -R whoogle:whoogle /opt/whoogle-search/"
eval "$SUDO systemctl enable --now whoogle"

echo "Installation finished!"
echo "Whoogle is now available at localhost:5000!"
