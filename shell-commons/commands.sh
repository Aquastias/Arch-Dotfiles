#!/usr/bin/env bash

function check_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: '$1' command not found"
    exit 127
  fi
}
