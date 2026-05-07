#!/usr/bin/env bash
# =============================================================================
# programs/virtualization/docker/install.sh
# =============================================================================
# Invoked by .os/lib/profiles.sh inside arch-chroot, as the owning user, with
# OS_DIR, PROGRAMS, SHELL_COMMONS pre-exported and temp NOPASSWD sudo granted.
#
# Installs docker + docker-compose via paru, enables the daemon (starts on
# first boot), and ensures the `docker` group exists. User membership in
# `docker` is declared per-user via user configs (groups: ["docker", ...]).
# =============================================================================

set -Eeuo pipefail
trap 'echo "[docker] error on line $LINENO" >&2' ERR

print_status info "Installing Docker..."
paru -S --noconfirm --needed --skipreview docker docker-compose

print_status info "Enabling Docker service (starts on first boot)..."
sudo systemctl enable docker.socket
sudo systemctl enable docker.service

# pacman creates the `docker` group as part of the docker package; this is a
# safety net if the package shape ever changes.
getent group docker >/dev/null || sudo groupadd docker

print_status success "Docker staged."
