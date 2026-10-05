#!/usr/bin/env bash
# =============================================================================
# programs/privacy/searxng/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as the owning user, with
# INSTALLER_DIR, PROGRAMS, SHELL_COMMONS pre-exported and temp NOPASSWD sudo
# granted.
#
# Checks podman is installed, seeds ~/.config/searxng (settings.yml with a
# fresh secret key, limiter.toml), and enables user linger so
# the quadlet services (home/, applied by Config Apply) start at boot without
# a login session. Container images are pulled on first start — podman is not
# running in the chroot.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[searxng] error on line $LINENO" >&2' ERR

if ! package_installed "podman"; then
  print_status error "podman must be installed before searxng" \
    "(declare it before searxng in programs)."
  exit 1
fi

mkdir -p "${HOME}/.config/searxng"
cp "${PROGRAMS}/privacy/searxng/settings.yml" \
  "${HOME}/.config/searxng/settings.yml"
sed -i "s|ultrasecretkey|$(openssl rand -hex 32)|g" \
  "${HOME}/.config/searxng/settings.yml"
cp "${PROGRAMS}/privacy/searxng/limiter.toml" "${HOME}/.config/searxng/"
print_status info "Seeded ~/.config/searxng/{settings.yml,limiter.toml}."

sudo mkdir -p /var/lib/systemd/linger
sudo touch "/var/lib/systemd/linger/${USER}"
print_status info "Linger enabled for ${USER}."
# podman-user-wait-network-online only polls network-online.target, which no
# system service pulls in on a pure or services-off host (it would time out
# at every boot): pull it in here.
sudo systemctl add-wants multi-user.target network-online.target
# podman-user-wait-network-online stays on: with linger the user manager
# starts at boot, so it delays only these containers, not the desktop, and
# keeps searxng's startup network check from crash-looping before the net.

print_status success "SearXNG staged." \
  "Quadlet units start on first boot; containers pulled then."
