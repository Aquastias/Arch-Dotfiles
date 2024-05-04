#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$SHELL_COMMONS/arrays.sh"
source "$SHELL_COMMONS/packages.sh"

ignore_pkgs=("teamspeak3" "whoogle")

# Install packages from repository
# shellcheck disable=SC2024
echo "Installing repo packages..."
eval "$SUDO pacman -S --needed - <pkglist-repo.txt"

# Install packages from AUR
echo "Installing AUR packages..."
if command -v paru &>/dev/null; then
  for pkg in $(<pkglist-aur.txt); do
    if ! package_installed "$pkg" && ! string_in_array "$pkg" "${ignore_pkgs[@]}"; then
      paru -S --noconfirm --skipreview "$pkg"
    else
      echo "$pkg is already installed."
    fi
  done
else
  echo "Please install paru!"
  exit 127
fi

# Execute teamspeak3 script
chmod +x ./teamspeak3/install.sh
./teamspeak3/install.sh

# Execute whoogle script
chmod +x ./whoogle/install.sh
./whoogle/install.sh

echo "All packages now installed!"
