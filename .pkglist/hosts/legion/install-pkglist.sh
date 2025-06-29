#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$SHELL_COMMONS/arrays.sh"
source "$SHELL_COMMONS/commands.sh"
source "$SHELL_COMMONS/packages.sh"
source "$SHELL_COMMONS/permissions.sh"

check_root
check_command "paru"

local ignore_pkgs=(
  "apparmor"
  "docker"
  "docker-compose"
  "grub"
  "paru"
)

# Install packages from repository
# shellcheck disable=SC2024
echo "Installing repo packages..."
paru -S --needed - <pkglist-repo.txt

# Install packages from AUR
echo "Installing AUR packages..."

for pkg in $(<pkglist-aur.txt); do
  if ! package_installed "$pkg" && ! array_contains "$pkg" "${ignore_pkgs[@]}"; then
    paru -S --noconfirm --skipreview "$pkg"
  else
    echo "$pkg is already installed."
  fi
done

# Make scripts executable
make_env_bash_scripts_executable ./programs

# Setup programs
local EXCLUDES=("teamspeak3")

for script in ./programs/*/install.sh; do
  dir_name=$(basename "$(dirname "$script")")

  # Skip if in exclude list
  if [[ " ${EXCLUDES[*]} " =~ " $dir_name " ]]; then
    echo "🚫 Skipping (excluded): $script"
    continue
  fi

  if [[ -f "$script" ]]; then
    echo
    echo "🔧 Running: $script"
    echo "------------------------------"
    "$script"
    echo "✅ Finished: $script"
    echo "=============================="
    echo
  else
    echo "⚠️  Not found or not a regular file: $script"
  fi
done

echo "All packages now installed!"
