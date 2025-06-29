#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$SHELL_COMMONS/commands.sh"
source "$SHELL_COMMONS/packages.sh"
source "$SHELL_COMMONS/permissions.sh"

check_root
check_command "paru"

echo "🔧 Installing Docker..."

paru -Sy --noconfirm docker docker-compose

echo "✅ Docker installed."

# Enable and start docker service
echo "🔧 Enabling and starting Docker service..."
systemctl enable --now docker.socket
systemctl enable --now docker.service
echo "✅ Docker service is running."

# Add the current (non-root) user to docker group
if [[ -n $SUDO_USER ]]; then
  user="$SUDO_USER"
  echo "🔧 Adding user '$user' to 'docker' group..."
  usermod -aG docker "$user"
  echo "✅ User '$user' added to docker group."
  echo "⚠️ You may need to log out and back in for group changes to take effect."
else
  echo "⚠️ Could not detect non-root user. Skipping usermod."
fi

echo "🎉 Docker setup complete!"
