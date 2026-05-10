#!/usr/bin/env bash
# lib/shell/directories.sh — directory existence helpers

function directory_exists() {
  [[ -d "$1" ]]
}

function check_directory() {
  if ! directory_exists "$1"; then
    echo "Error: directory '$1' not found" >&2
    exit 1
  fi
}
