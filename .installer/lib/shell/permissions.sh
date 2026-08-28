#!/usr/bin/env bash
# lib/shell/permissions.sh — root checking and script permission helpers

function check_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "This script must be run as root" >&2
    exit 1
  fi
}
