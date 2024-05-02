#!/usr/bin/env bash

skin_addon_url="https://addons-content.teamspeak.com/3bfce85f-bed4-4b04-a183-41b2b42107b4/files/6/Demus13_5d07e6700bc67.ts3_style"
icon_pack_addon_url="https://addons-content.teamspeak.com/4f8b0ebf-eb4a-4c37-9c4f-366813ffcf79/files/1/Material4Teamspeak_white.ts3_iconpack"

function package_installed() {
  pacman -Q "$1" &>/dev/null
}

function check_url_not_404() {
  local url="$1"
  local response

  # Send a HEAD request to the URL and suppress output
  response=$(curl -s -o /dev/null -w "%{http_code}" "$url")

  if [ "$response" != "404" ]; then
    return 0
  else
    return 1
  fi
}

if ! command -v paru &>/dev/null; then
  echo "paru is not installed!"
  exit 127
fi

if check_url_not_404 "$skin_addon_url"; then
  echo "Skin addon url is dead"
  exit 0
fi

if check_url_not_404 "$icon_pack_addon_url"; then
  echo "Icon pack addon url is dead"
  exit 0
fi

if ! package_installed "teamspeak3"; then
  paru -S --noconfirm --skipreview teamspeak3
fi

if ! package_installed "teamspeak3-addon-installer"; then
  paru -S --noconfirm --skipreview teamspeak3-addon-installer
fi

teamspeak3-install-addon "$skin_addon_url"
teamspeak3-install-addon "$icon_pack_addon_url"
