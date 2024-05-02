#!/usr/bin/env bash

function package_installed() {
    pacman -Q "$1" &>/dev/null
}

# Install packages from repository
sudo pacman -S --needed - <pkglist-repo.txt

# Install packages from AUR
if command -v paru &>/dev/null; then
    for pkg in $(<pkglist-aur.txt); do
        if ! package_installed "$pkg"; then
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
fi
