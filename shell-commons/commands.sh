#!/usr/bin/env bash

function command_exists() {
  command -v "$1" >/dev/null 2>&1
}

function check_command() {
  if ! command_exists "$1"; then
    echo "Error: '$1' command not found"
    exit 127
  fi
}
