#!/usr/bin/env bash

# shellcheck disable=SC2024
sudo pacman -S --needed - <pkglist-repo.txt

if command -v paru -S --skipreview &>/dev/null; then
  for x in $(<pkglist-aur.txt); do paru -S --skipreview "$x"; done
else
  if command -v yay -S --noconfirm --mflags --skipinteg &>/dev/null; then
    for x in $(<pkglist-aur.txt); do yay -S --noconfirm --mflags --skipinteg "$x"; done
  else
    echo "Please install paru or yay."
  fi
fi
