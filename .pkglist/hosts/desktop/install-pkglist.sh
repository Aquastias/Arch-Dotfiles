#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$SHELL_COMMONS/arrays.sh"
source "$SHELL_COMMONS/commands.sh"
source "$SHELL_COMMONS/packages.sh"
source "$SHELL_COMMONS/permissions.sh"

check_root
check_command "paru"

ignore_pkgs=("apparmor" "grub" "teamspeak3")

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

# Setup AppArmor
./programs/apparmor/install.sh

# Execute SearxNG scripts
./programs/searxng/install.sh
./programs/searxng/update.sh

# Execute TeamSpeak3 script
./programs/teamspeak3/install.sh

echo "All packages now installed!"
