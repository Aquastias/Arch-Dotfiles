#!/usr/bin/env bash

function send_user_notification() {
  local title="$1"
  local message="$2"
  local icon="${3:-dialog-information}"
  local app_name="${4:-Notification}"
  local timeout="${5:-15000}"
  local desktop_entry="${6:-$app_name}"

  if [ -z "$SUDO_USER" ]; then
    echo "This function must be run with sudo."
    return 1
  fi

  # Get the UID and DBUS address of the SUDO_USER
  local user_id
  user_id=$(id -u "$SUDO_USER")

  local dbus_address="/run/user/$user_id/bus"

  # Check if user has an active graphical session and a DBus address
  if [ -S "$dbus_address" ]; then
    if loginctl show-user "$SUDO_USER" | grep -q 'Display='; then
      "$SUDO" -u "$SUDO_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="unix:path=$dbus_address" \
        notify-send -a "$app_name" \
        -h "string:desktop-entry:$desktop_entry" \
        -t "$timeout" \
        -i "$icon" \
        "$title" \
        "$message"
    fi
  fi
}
