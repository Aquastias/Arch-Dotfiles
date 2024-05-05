#!/usr/bin/env bash

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

# Path to the sudoers file
sudoers_file="/etc/sudoers"

# Backup sudoers file
cp "$sudoers_file" "$sudoers_file.bak"

# Uncomment the line "Defaults env_keep += "HOME"" and add the new line after it
# shellcheck disable=SC2016
sed -i 's/^# Defaults env_keep += "HOME"/Defaults env_keep += "HOME"/' "$sudoers_file"

if ! grep -Rq 'Defaults env_keep += "SHELL_COMMONS"' "$sudoers_file"; then
  sed -i '/Defaults env_keep += "HOME"/aDefaults env_keep += "SHELL_COMMONS"' "$sudoers_file"
fi

if ! grep -Rq 'Defaults env_keep += "DOTFILES"' "$sudoers_file"; then
  if grep -Rq 'Defaults env_keep += "SHELL_COMMONS"' "$sudoers_file"; then
    sed -i '/Defaults env_keep += "SHELL_COMMONS"/aDefaults env_keep += "DOTFILES"' "$sudoers_file"
  fi
fi

echo "Changes applied to $sudoers_file"
