#!/usr/bin/env bash

# Checks if the script is being run as root
function check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
  fi
}

function make_env_bash_scripts_executable() {
  local target_dir="${1:-.}"

  # Find all files and check for exact shebang
  while IFS= read -r -d '' file; do
    if head -n 1 "$file" | grep -q '^#!/usr/bin/env bash$'; then
      chmod +x "$file"
      echo "Made executable: $file"
    fi
  done < <(find "$target_dir" -type f -print0)

  echo "Finished setting executable permissions for scripts with '#!/usr/bin/env bash'."
}

function make_executable_and_run() {
  local script="$1"

  if [ -z "$script" ]; then
    echo "Usage: make_executable_and_run /path/to/script"
    return 1
  fi

  if [ ! -f "$script" ]; then
    echo "Error: File not found: $script"
    return 1
  fi

  chmod +x "$script" && "$script"
}
