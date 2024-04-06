#!/usr/bin/env bash

# Kill and restart Waybar whenever its config files change
CONFIG_DIRECTORY="$HOME/.config/waybar/"
WAYBAR_PROCESS_NAME="waybar"

if ! command -v "$WAYBAR_PROCESS_NAME" &> /dev/null; then
  echo "$WAYBAR_PROCESS_NAME command not found! Exiting..."
  exit 127
fi

if ! command -v inotifywait &> /dev/null; then
  echo 'inotifywait command not found! Exiting...'
  exit 127
fi

if ! command -v logger &> /dev/null; then
  echo 'logger command not found! Exiting...'
  exit 127
fi

if ! command -v killall &> /dev/null; then
  echo 'killall command not found! Exiting...'
  exit 127
fi

trap 'killall "$WAYBAR_PROCESS_NAME"' EXIT

# Function to restart Waybar
restart_waybar() {
  logger -i "$0: Restarting Waybar..."
  killall "$WAYBAR_PROCESS_NAME" 2>/dev/null
  sleep 1
  waybar &
}

# Initial checksum of all config files
last_checksum=$(find "${CONFIG_DIRECTORY}" -type f -exec md5sum {} + | sort | md5sum | awk '{print $1}')

# Flag to track whether Waybar is running
waybar_running=false

while true; do
  if [ "$waybar_running" = false ]; then
    logger -i "$0: Starting Waybar in the background..."
    waybar &
    logger -i "$0: Started Waybar (PID=$!). Waiting for modifications to ${CONFIG_DIRECTORY}..."
    waybar_running=true
  fi

  # Use inotifywait to detect changes in the directory
  inotifywait -e modify,create,delete -r "${CONFIG_DIRECTORY}" |
    while read -r _directory _events _filename; do
      # Check if there are actual changes in config files
      current_checksum=$(find "${CONFIG_DIRECTORY}" -type f -exec md5sum {} + | sort | md5sum | awk '{print $1}')

      if [ "$current_checksum" != "$last_checksum" ]; then
        logger -i "$0: Detected changes in ${CONFIG_DIRECTORY}."
        restart_waybar
        last_checksum="$current_checksum"
      fi
    done
done
