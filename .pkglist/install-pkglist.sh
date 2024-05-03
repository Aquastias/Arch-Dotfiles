#!/usr/bin/env bash

function package_installed() {
  pacman -Q "$1" &>/dev/null
}

function string_in_array() {
  local string="$1"
  local array=("$2")
  local found=0

  for element in "${array[@]}"; do
    if [ "$element" == "$string" ]; then
      found=1
      break
    fi
  done

  if [ $found -eq 1 ]; then
    return 0
  else
    return 1
  fi
}

ignore_pkgs=("teamspeak3")

# Install packages from repository
# shellcheck disable=SC2024
echo "Installing repo packages..."
sudo pacman -S --needed - <pkglist-repo.txt

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
elif command -v yay &>/dev/null; then
  for pkg in $(<pkglist-aur.txt); do
    if ! package_installed "$pkg"; then
      yay -S --noconfirm --mflags --skipinteg "$pkg"
    else
      echo "$pkg is already installed."
    fi
  done
else
  echo "Please install paru or yay."
  exit 127
fi

# Execute teamspeak3 script
chmod +x ./teamspeak3/install.sh
./teamspeak3/install.sh

echo "All packages now installed!"
