#!/usr/bin/env bash

function directory_exists() {
  if [ -d "$1" ]; then
    return 0
  else
    return 1
  fi
}

function check_directory() {
  if ! directory_exists "$1"; then
    echo "Error: '$1' command not found"
    exit 1
  fi
}
