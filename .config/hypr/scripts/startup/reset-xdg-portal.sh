#!/usr/bin/env bash

sleep 1

# Kill all xdg-desktop-portal processes
killall xdg-desktop-portal-hyprland
killall xdg-desktop-portal-gnome
killall xdg-desktop-portal-kde
killall xdg-desktop-portal-lxqt
killall xdg-desktop-portal-wlr
killall xdg-desktop-portal

sleep 1

hyprland_portal=/usr/lib/xdg-desktop-portal-hyprland
default_portal=/usr/lib/xdg-desktop-portal

if ! command -v $hyprland_portal &> /dev/null; then
  echo 'xdg-desktop-portal-hyprland command not found! Exiting ...'
  exit 127
fi

if ! command -v $default_portal &> /dev/null; then
  echo 'xdg-desktop-portal command not found! Exiting ...'
  exit 127
fi

# Start xdg-desktop-portal-hyprland
/usr/lib/xdg-desktop-portal-hyprland &

sleep 2

# Start xdg-desktop-portal
/usr/lib/xdg-desktop-portal &

# Send command to Dbus
sleep 1 && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP

# Import environment with systemd
sleep 1 && systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP