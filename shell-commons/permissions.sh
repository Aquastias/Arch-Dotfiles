#!/usr/bin/env bash

# Checks if the script is being run as root
function check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
  fi
}
