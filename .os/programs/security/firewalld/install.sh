#!/usr/bin/env bash
# =============================================================================
# programs/security/firewalld/install.sh
# =============================================================================
# Invoked by .os/lib/profiles.sh inside arch-chroot, as the owning user, with
# OS_DIR, PROGRAMS, SHELL_COMMONS pre-exported and temp NOPASSWD sudo granted.
#
# Installs firewalld via paru, enables the service, and seeds zone rules for
# libvirt bridge networking. Daemon is not running inside the chroot —
# firewall-offline-cmd writes on-disk config; rules apply on first boot.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[firewalld] error on line $LINENO" >&2' ERR

ZONE="public"
BRIDGE_IF="virbr0"
SUBNET="192.168.122.0/24"

if command_exists "ufw"; then
  print_status error "ufw is installed; firewalld and ufw cannot coexist."
  exit 1
fi

print_status info "Installing firewalld..."
paru -S --noconfirm --needed firewalld

print_status info "Enabling firewalld at boot..."
sudo systemctl enable firewalld

print_status info "Seeding zone '${ZONE}' rules..."
sudo firewall-offline-cmd --zone="${ZONE}" --add-service=dhcp
sudo firewall-offline-cmd --zone="${ZONE}" --add-service=dns
sudo firewall-offline-cmd --zone="${ZONE}" --add-interface="${BRIDGE_IF}"
sudo firewall-offline-cmd --zone="${ZONE}" --add-masquerade
sudo firewall-offline-cmd --direct --add-rule ipv4 nat POSTROUTING 0 \
  -s "${SUBNET}" -j MASQUERADE

print_status success "firewalld installed and configured" \
  "(will start on first boot)."
