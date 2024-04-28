#!/usr/bin/env bash

# shellcheck disable=SC2024
sudo pacman -S --needed - <pkglist-repo.txt

if command -v paru -S --skipreview &>/dev/null; then
  for x in $(<pkglist-aur.txt); do paru -S "$x"; done
else
  if command -v yay -S --noconfirm --mflags --skipinteg &>/dev/null; then
    for x in $(<pkglist-aur.txt); do yay -S "$x"; done
  else
    echo "Please install an AUR helper https://wiki.archlinux.org/title/AUR_helpers"
  fi
fi
