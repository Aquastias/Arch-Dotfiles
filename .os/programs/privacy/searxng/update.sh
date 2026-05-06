#!/usr/bin/env bash
# =============================================================================
# programs/privacy/searxng/update.sh
# =============================================================================
# Re-runnable helper for an already-installed SearxNG container stack.
# Invoke after first boot, not during chroot install (docker daemon is not
# running inside the chroot). Sources shell-stdlib.sh for print_status /
# package_installed.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[searxng:update] error on line $LINENO" >&2' ERR

# shellcheck source=/dev/null
source "${SHELL_COMMONS}/shell-stdlib.sh"

if ! package_installed "docker"; then
  print_status error "Docker not found. Please make sure Docker is installed and in your PATH."
  exit 1
fi

docker_src=$(command -v docker)
if [[ ! -L "/usr/local/bin/docker" ]]; then
  ln -s "$docker_src" "/usr/local/bin/docker"
fi

if [[ -d "/usr/local/searxng-docker" ]]; then
  cd "/usr/local/searxng-docker"
  git pull
  docker compose pull
  docker compose up -d
else
  print_status error "SearxNG Docker repo has not been cloned on this host."
  exit 1
fi
