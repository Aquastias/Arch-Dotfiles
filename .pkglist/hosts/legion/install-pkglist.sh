#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$SHELL_COMMONS/arrays.sh"
source "$SHELL_COMMONS/commands.sh"
source "$SHELL_COMMONS/packages.sh"
source "$SHELL_COMMONS/permissions.sh"

check_root
check_command "paru"

ignore_pkgs=("teamspeak3")

# Install packages from repository
# shellcheck disable=SC2024
echo "Installing repo packages..."
pacman -S --needed - <pkglist-repo.txt

# Install packages from AUR
echo "Installing AUR packages..."

for pkg in $(<pkglist-aur.txt); do
  if ! package_installed "$pkg" && ! array_contains "$pkg" "${ignore_pkgs[@]}"; then
    paru -S --noconfirm --skipreview "$pkg"
  else
    echo "$pkg is already installed."
  fi
done

# Setup AppArmor
chmod +x ./programs/apparmor/install.sh && ./programs/apparmor/install.sh

# Execute SearxNG scripts
chmod +x ./programs/searxng/install.sh && ./programs/searxng/install.sh
chmod +x ./programs/searxng/update.sh && ./programs/searxng/update.sh

echo "All packages now installed!"
