#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$SHELL_COMMONS/commands.sh"
source "$SHELL_COMMONS/permissions.sh"
source "$SHELL_COMMONS/packages.sh"

check_root
check_command "paru"

if ! package_installed "whoogle"; then
  paru -S --skipreview --noconfirm whoogle
fi

sleep 5

chown -R whoogle:whoogle /opt/whoogle-search/
systemctl enable --now whoogle

echo "Whoogle is now available at localhost:5000!"
