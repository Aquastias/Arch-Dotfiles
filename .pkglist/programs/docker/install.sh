#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$SHELL_COMMONS/commands.sh"
source "$SHELL_COMMONS/permissions.sh"
source "$SHELL_COMMONS/strings.sh"

check_root
check_command "paru"

print_status info "Installing Docker..."

paru -S --skipreview --noconfirm docker docker-compose

print_status success "Docker installed."

# Enable and start docker service
print_status info "Enabling and starting Docker service..."
systemctl enable --now docker.socket
systemctl enable --now docker.service
print_status success "Docker service is running."

# Add the current (non-root) user to docker group
if [[ -n $SUDO_USER ]]; then
  user="$SUDO_USER"
  print_status info "Adding user '$user' to 'docker' group..."
  usermod -aG docker "$user"
  print_status success "User '$user' added to docker group."
  print_status warning "You may need to log out and back in for group changes to take effect."
else
  print_status warning "Could not detect non-root user. Skipping usermod."
fi

print_status success "Docker setup complete!"
