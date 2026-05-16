#!/usr/bin/env bash
# =============================================================================
# programs/privacy/searxng/install.sh
# =============================================================================
# Invoked by .os/lib/profiles.sh inside arch-chroot, as the owning user, with
# OS_DIR, PROGRAMS, SHELL_COMMONS pre-exported and temp NOPASSWD sudo granted.
#
# Checks podman is installed, seeds ~/.config/searxng/settings.yml with a
# fresh secret key, and enables user linger via /var/lib/systemd/linger so
# the quadlet services start at boot without a login session. Container images
# are pulled on first start — podman is not running in the chroot.
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
print_status info "Seeded ~/.config/searxng/settings.yml."

sudo mkdir -p /var/lib/systemd/linger
sudo touch "/var/lib/systemd/linger/${USER}"
print_status info "Linger enabled for ${USER}."

print_status success "SearXNG staged." \
  "Quadlet units start on first boot; containers pulled then."
