#!/usr/bin/env bash
# lib/shell/commands.sh — command existence and execution helpers

function command_exists() {
  command -v "$1" >/dev/null 2>&1
}

function check_command() {
  if ! command_exists "$1"; then
    echo "Error: '$1' command not found" >&2
    exit 127
  fi
}

function command_output_contains() {
  local command_output
  # shellcheck disable=SC2294
  # Callers pass arbitrary command strings (e.g. "lsblk -dno NAME") that may
  # contain pipes/options; eval is required for shell-string semantics.
  command_output=$(eval "$1")
  string_contains "$command_output" "$2"
}
