#!/usr/bin/env bash
# =============================================================================
# programs/privacy/searxng/install.sh
# =============================================================================
# Invoked by .os/lib/profiles.sh inside arch-chroot, as the owning user, with
# OS_DIR, PROGRAMS, SHELL_COMMONS pre-exported and temp NOPASSWD sudo granted.
#
# Clones searxng-docker into /usr/local, seeds settings.yml with a fresh
# secret, opens http/https in whichever firewall is installed (offline), and
# enables the systemd unit so the docker stack starts on first boot.
# Container pull/up is deferred to update.sh post-boot — docker is not
# running here.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[searxng] error on line $LINENO" >&2' ERR

# shellcheck source=/dev/null
source "${SHELL_COMMONS}/shell-stdlib.sh"

if ! package_installed "docker"; then
  print_status error "Docker must be installed before searxng (declare it in system_programs first)."
  exit 1
fi

# Open http/https in whichever firewall is present. Use offline modes since
# the daemon is not running inside the chroot.
if package_installed "firewalld"; then
  print_status info "Opening http/https in firewalld (offline)..."
  sudo firewall-offline-cmd --zone=public --add-service=http
  sudo firewall-offline-cmd --zone=public --add-service=https
elif package_installed "ufw"; then
  print_status info "Opening http/https in ufw..."
  sudo ufw allow http
  sudo ufw allow https
else
  print_status warning "Neither firewalld nor ufw installed; skipping firewall rules."
fi

if [[ ! -d "/usr/local/searxng-docker" ]]; then
  print_status info "Cloning searxng-docker into /usr/local..."
  sudo git clone https://github.com/searxng/searxng-docker.git /usr/local/searxng-docker

  print_status info "Seeding settings.yml..."
  sudo rm -f /usr/local/searxng-docker/searxng/settings.yml
  sudo cp "${PROGRAMS}/privacy/searxng/settings.yml" /usr/local/searxng-docker/searxng/settings.yml
  sudo sed -i "s|ultrasecretkey|$(openssl rand -hex 32)|g" /usr/local/searxng-docker/searxng/settings.yml

  print_status info "Enabling searxng-docker.service (will start on first boot)..."
  sudo cp /usr/local/searxng-docker/searxng-docker.service.template /usr/local/searxng-docker/searxng-docker.service
  sudo systemctl enable /usr/local/searxng-docker/searxng-docker.service
else
  print_status info "SearxNG docker is already installed!"
fi

print_status success "searxng staged for $(whoami) (containers start on first boot; run update.sh to refresh)."
