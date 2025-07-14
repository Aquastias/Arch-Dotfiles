#!/usr/bin/env bash

set -euo pipefail
trap 'echo "Error on line $LINENO"' ERR

# shellcheck source=/dev/null
source "$SHELL_COMMONS/commands.sh"
source "$SHELL_COMMONS/permissions.sh"
source "$SHELL_COMMONS/strings.sh"

check_root
check_command "paru"

print_status info "Installing UFW..."
paru -S --skipreview --noconfirm ufw

print_status info "Resetting UFW to defaults..."
ufw --force reset

print_status info "Setting default policy: deny incoming, allow outgoing..."
ufw default deny incoming
ufw default allow outgoing

print_status info "Adding rules for libvirt (DHCP, DNS, and virbr0 bridge traffic)..."
# Allow DHCP client traffic
ufw allow out 67,68/udp comment 'Allow DHCP for VMs'
# Allow DNS lookups
ufw allow out 53/udp comment 'Allow DNS for VMs'
# Allow all traffic on virbr0 (libvirt default NAT bridge)
ufw allow in on virbr0 comment 'Allow incoming VM traffic'
ufw allow out on virbr0 comment 'Allow outgoing VM traffic'

print_status info "Enabling UFW..."
ufw --force enable

print_status info "UFW rules applied. Current status:"
ufw status verbose

print_status success "UFW installed successfully."
