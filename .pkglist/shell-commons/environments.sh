#!/usr/bin/env bash

function get_desktop_env() {
  if [ "$XDG_CURRENT_DESKTOP" ]; then
    case "$XDG_CURRENT_DESKTOP" in
    *KDE*) echo "KDE" ;;
    *Hyprland*) echo "Hyprland" ;;
    *) echo "$XDG_CURRENT_DESKTOP" ;;
    esac
    return
  fi

  # Wayland fallback
  if [ "$WAYLAND_DISPLAY" ]; then
    if pgrep -x hyprland >/dev/null 2>&1; then
      echo "Hyprland"
    elif pgrep -x kwin_wayland >/dev/null 2>&1; then
      echo "KDE"
    else
      echo "Wayland"
    fi
    return
  fi

  # X11 fallback
  if [ "$DISPLAY" ]; then
    if pgrep -x kwin_x11 >/dev/null 2>&1; then
      echo "KDE"
    else
      echo "X11"
    fi
    return
  fi

  echo "Unknown"
}

function is_kde() {
  [[ "$(get_desktop_env)" == "KDE" ]]
}

function is_hyprland() {
  [[ "$(get_desktop_env)" == "Hyprland" ]]
}
