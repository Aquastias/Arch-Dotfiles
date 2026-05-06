#!/usr/bin/env bash
# =============================================================================
# programs/security/firewalld/install.sh
# =============================================================================
# Invoked by .os/lib/profiles.sh inside arch-chroot, as root.
# Env vars provided by the runner: OS_DIR, PROGRAMS, SHELL_COMMONS.
#
# Installs firewalld via pacman, enables the service, and seeds zone rules
# for libvirt bridge networking. Mirrors the legacy script under
# .pkglist/programs/security/firewalld/ but uses pacman instead of paru
# because system programs must come from official repos.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[firewalld] error on line $LINENO" >&2' ERR

# shellcheck source=/dev/null
source "${SHELL_COMMONS}/shell-stdlib.sh"

ZONE="public"
BRIDGE_IF="virbr0"
SUBNET="192.168.122.0/24"

if check_command "ufw"; then
  print_status error "ufw is installed; firewalld and ufw cannot coexist."
  exit 1
fi

print_status info "Installing firewalld..."
pacman -S --noconfirm --needed firewalld

print_status info "Enabling firewalld at boot..."
# `systemctl enable --now` does not work inside an unbooted chroot; only enable.
systemctl enable firewalld

# All firewall-cmd calls run with --offline so they edit on-disk config without
# needing the daemon running inside the chroot.
print_status info "Seeding zone '${ZONE}' rules..."
firewall-offline-cmd --zone="${ZONE}" --add-service=dhcp
firewall-offline-cmd --zone="${ZONE}" --add-service=dns
firewall-offline-cmd --zone="${ZONE}" --add-service=http
firewall-offline-cmd --zone="${ZONE}" --add-service=https
firewall-offline-cmd --zone="${ZONE}" --add-interface="${BRIDGE_IF}"
firewall-offline-cmd --zone="${ZONE}" --add-masquerade
firewall-offline-cmd --direct --add-rule ipv4 nat POSTROUTING 0 \
  -s "${SUBNET}" -j MASQUERADE

print_status success "firewalld installed and configured (will start on first boot)."
