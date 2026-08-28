#!/usr/bin/env bash
# lib/shell/commands.sh — command existence and execution helpers

function command_exists() {
  command -v "$1" >/dev/null 2>&1
}
