#!/usr/bin/env bash

if ! command -v swww &>/dev/null; then
  echo 'swww command not found! Exiting...'
  exit 127
fi

if ! command -v waypaper &>/dev/null; then
  echo 'waypaper command not found! Exiting...'
  exit 127
fi

# Start the daemon
sleep 1 && (swww query || swww init)

# Initialize GUI
sleep 1 && waypaper --restore --backend swww