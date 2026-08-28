#!/usr/bin/env bash
# =============================================================================
# programs/virtualization/docker/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as the owning user, with
# INSTALLER_DIR, PROGRAMS, SHELL_COMMONS pre-exported and temp NOPASSWD sudo
# granted.
#
# Installs docker + docker-compose via paru, enables the socket for on-demand
# daemon activation (starts on first client connection), and ensures the
# `docker` group exists. User membership in `docker` is declared per-user
# via user configs (groups: ["docker", ...]).
# =============================================================================

set -Eeuo pipefail
trap 'echo "[docker] error on line $LINENO" >&2' ERR

print_status info "Installing Docker..."
${AUR_HELPER} -S --noconfirm --needed docker docker-compose

print_status info "Enabling Docker socket" \
  "(daemon starts on first connection)..."
sudo systemctl enable docker.socket

# On-demand only: keep docker.service off the boot path so it can't drag
# network-online.target into startup. Package/preset may have enabled it.
sudo systemctl disable docker.service 2>/dev/null || true

# pacman creates the `docker` group as part of the docker package; this is a
# safety net if the package shape ever changes.
getent group docker >/dev/null || sudo groupadd docker

print_status success "Docker staged."
