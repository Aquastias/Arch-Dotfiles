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

print_status info "Adding NAT masquerading for libvirt VMs in /etc/ufw/before.rules..."

# Detect external interface (default route interface)
# EXT_IF=$(ip route | awk '/default/ {print $5; exit}')
EXT_IF=$(ip route show default 0.0.0.0/0 | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')

if [[ -z "$EXT_IF" ]]; then
  print_status warning "Could not detect external network interface. Please set EXT_IF manually."
  exit 1
fi

BEFORE_RULES="/etc/ufw/before.rules"

if [ ! -f "${BEFORE_RULES}.bak" ]; then
  cp "$BEFORE_RULES" "${BEFORE_RULES}.bak"
fi

# Insert NAT masquerade rules before *filter line if not already present
# 192.168.122.0/24 = The virtual network range where VMs live by default.
if ! grep -q 'POSTROUTING -s 192.168.122.0/24 -o' "$BEFORE_RULES"; then
  # Insert nat rules before the *filter line
  sed -i '/^\*filter/i \
# NAT table rules for libvirt VMs\n\
*nat\n\
:POSTROUTING ACCEPT [0:0]\n\
-A POSTROUTING -s 192.168.122.0/24 -o '"$EXT_IF"' -j MASQUERADE\n\
COMMIT\n' "$BEFORE_RULES"
  print_status success "NAT masquerade rules added to $BEFORE_RULES"
else
  print_status info "NAT masquerade rules already exist in $BEFORE_RULES"
fi

print_status info "Enabling UFW..."
ufw --force enable
ufw reload

print_status info "UFW rules applied. Current status:"
ufw status verbose

print_status success "UFW installed successfully."
