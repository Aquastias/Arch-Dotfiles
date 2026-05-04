#!/usr/bin/env zsh

system_upgrade() {
  if command -v paru &>/dev/null; then
    paru -Syyu --newsonupgrade || { echo "Failed to upgrade using paru" >&2; return 1; }
  else
    $SUDO pacman -Syyu || { echo "Failed to upgrade using pacman" >&2; return 1; }
  fi
}

alias system-upgrade='system_upgrade'
