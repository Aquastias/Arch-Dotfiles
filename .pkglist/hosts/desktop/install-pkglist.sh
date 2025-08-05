#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$SHELL_COMMONS/arrays.sh"
# shellcheck source=/dev/null
source "$SHELL_COMMONS/commands.sh"
# shellcheck source=/dev/null
source "$SHELL_COMMONS/packages.sh"
# shellcheck source=/dev/null
source "$SHELL_COMMONS/permissions.sh"
# shellcheck source=/dev/null
source "$SHELL_COMMONS/strings.sh"

check_root

if ! command_exists "paru"; then
  if [[ -f "$PROGRAMS/paru/install.sh" ]]; then
    make_executable_and_run "$PROGRAMS/paru/install.sh"
  else
    print_status warning "Not found or not a regular file: $PROGRAMS/paru/install.sh"
  fi
fi

ignore_pkgs=()

while IFS= read -r dir; do
  ignore_pkgs+=("$dir")
done < <(find "$PROGRAMS"/ -mindepth 2 -maxdepth 2 -type d -exec basename {} \;)

# Install packages from repository
# shellcheck disable=SC2024
print_status info "Installing repo packages..."
paru -S --needed - <pkglist-repo.txt

# Install packages from AUR
print_status info "Installing AUR packages..."

for pkg in $(<pkglist-aur.txt); do
  if ! package_installed "$pkg" && ! array_contains "$pkg" "${ignore_pkgs[@]}"; then
    "$SUDO" -u "$SUDO_USER" paru -S --noconfirm --skipreview "$pkg"
  else
    print_status info "$pkg is already installed."
  fi
done

# Make scripts executable
make_env_bash_scripts_executable "$PROGRAMS"

# Setup programs
EXCLUDES=()

for script in "$PROGRAMS"/**/*/install.sh; do
  dir_name=$(basename "$(dirname "$script")")

  # Skip if in exclude list
  if [[ " ${EXCLUDES[*]} " =~ $dir_name ]]; then
    print_status info "Skipping (excluded): $script"
    continue
  fi

  if [[ -f "$script" ]]; then
    print_status info "\nRunning: $script"
    print_status info "------------------------------"
    "$script"
    print_status success "\nFinished: $script"
    print_status success "==============================\n"
  else
    print_status warning "Not found or not a regular file: $script"
  fi
done

print_status success "All packages are now installed!"
