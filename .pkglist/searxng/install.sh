#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$SHELL_COMMONS/commands.sh"
source "$SHELL_COMMONS/packages.sh"
source "$SHELL_COMMONS/permissions.sh"

check_root
check_command "paru"

# Symlink docker in /usr/local/bin
if ! package_installed "docker"; then
  echo "Docker not found. Please make sure Docker is installed and in your PATH."
  exit 1
else
  docker_src=$(command -v docker)

  if [ ! -L "/usr/local/bin/docker" ]; then
    ln -s "$docker_src" "/usr/local/bin"
  fi
fi

# Enable http and https in firewalld
if ! package_installed "firewalld"; then
  paru -S --skipreview --noconfirm firewalld
  systemctl enable --now firewalld
fi

if ! firewall-cmd --zone=public --list-services | grep -q -w "http" && ! firewall-cmd --zone=public --list-services | grep -q -w "https"; then
  echo "Firewall http or https service is not enabled in the public zone. Enabling..."

  firewall-cmd --permanent --zone=public --add-service=http
  firewall-cmd --permanent --zone=public --add-service=https
  firewall-cmd --reload
else
  echo "Firewall http and https services are enabled in the public zone!"
fi

if [ ! -d "/usr/local/searxng-docker" ]; then
  # Clone repo
  cd /usr/local || exit
  git clone https://github.com/searxng/searxng-docker.git
  cd searxng-docker || exit

  # Prepare settings
  rm -f searxng/settings.yml
  cp "$DOTFILES/.pkglist/searxng/settings.yml" searxng
  sed -i "s|ultrasecretkey|$(openssl rand -hex 32)|g" searxng/settings.yml

  # Start services
  cp searxng-docker.service.template searxng-docker.service
  systemctl enable --now "$(pwd)"/searxng-docker.service
else
  echo "SearxNG docker is already installed!"
fi
