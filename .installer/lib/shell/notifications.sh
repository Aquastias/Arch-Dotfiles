#!/usr/bin/env bash
# lib/shell/notifications.sh — desktop notification helpers
# (requires sudo context)

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

# seat0_user — the user of the graphical (seat0) session, if any; never a
# greeter's account (only "user"-class sessions count). Nothing when none.
seat0_user() {
  local _session _uid user seat _leader class _rest
  # loginctl list-sessions columns: SESSION UID USER SEAT LEADER CLASS …
  while read -r _session _uid user seat _leader class _rest; do
    if [[ "$seat" == seat0 && "$class" == user ]]; then
      printf '%s\n' "$user"
      return 0
    fi
  done < <(loginctl list-sessions --no-legend 2>/dev/null)
  return 0
}
