#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$SHELL_COMMONS/packages.sh"
source "$SHELL_COMMONS/strings.sh"

# Symlink docker in /usr/local/bin
if ! package_installed "docker"; then
  print_status error "Docker not found. Please make sure Docker is installed and in your PATH."
  exit 1
else
  docker_src=$(command -v docker)

  if [ ! -L "/usr/local/bin/docker" ]; then
    ln -s "$docker_src" "/usr/local/bin"
  fi
fi

if [ -d "/usr/local/searxng-docker" ]; then
  cd "/usr/local/searxng-docker" || exit

  git pull
  docker compose pull
  docker compose up -d
else
  print_status error "SearxNG Docker repo has not been cloned on this host."
fi
