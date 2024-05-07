#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$SHELL_COMMONS/strings.sh"

function command_exists() {
  command -v "$1" >/dev/null 2>&1
}

function check_command() {
  if ! command_exists "$1"; then
    echo "Error: '$1' command not found"
    exit 127
  fi
}

function command_output_contains() {
  command_output=$(eval "$1")
  substring="$2"

  string_contains "$command_output" "$substring"
}
