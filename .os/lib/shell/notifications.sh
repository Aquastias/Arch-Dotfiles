#!/usr/bin/env bash
# lib/shell/notifications.sh — desktop notification helpers (requires sudo context)

function send_user_notification() {
  local title="$1"
  local message="$2"
  local icon="${3:-dialog-information}"
  local app_name="${4:-Notification}"
  local timeout="${5:-15000}"
  local desktop_entry="${6:-$app_name}"

  if [[ -z "${SUDO_USER:-}" ]]; then
    echo "This function must be run with sudo." >&2
    return 1
  fi

  local user_id dbus_address
  user_id="$(id -u "$SUDO_USER")"
  dbus_address="/run/user/${user_id}/bus"

  if [[ -S "$dbus_address" ]]; then
    if loginctl show-user "$SUDO_USER" | grep -q 'Display='; then
      sudo -u "$SUDO_USER" \
        DISPLAY=:0 \
        DBUS_SESSION_BUS_ADDRESS="unix:path=${dbus_address}" \
        notify-send -a "$app_name" \
        -h "string:desktop-entry:${desktop_entry}" \
        -t "$timeout" \
        -i "$icon" \
        "$title" \
        "$message"
    fi
  fi
}
