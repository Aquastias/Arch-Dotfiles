#!/usr/bin/env bash
# lib/shell/permissions.sh — root checking and script permission helpers

function check_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "This script must be run as root" >&2
    exit 1
  fi
}

function make_env_bash_scripts_executable() {
  local target_dir="${1:-.}"
  while IFS= read -r -d '' file; do
    if head -n 1 "$file" | grep -q '^#!/usr/bin/env bash$'; then
      chmod +x "$file"
      echo "Made executable: $file"
    fi
  done < <(find "$target_dir" -type f -print0)
  echo "Finished setting executable permissions."
}

function make_executable_and_run() {
  local script="$1"
  if [[ -z "$script" ]]; then
    echo "Usage: make_executable_and_run /path/to/script" >&2
    return 1
  fi
  if [[ ! -f "$script" ]]; then
    echo "Error: File not found: $script" >&2
    return 1
  fi
  chmod +x "$script" && "$script"
}
