#!/usr/bin/env bash

set -euo pipefail
trap 'echo "Error on line $LINENO"' ERR

# shellcheck source=/dev/null
source "$SHELL_COMMONS/commands.sh"
# shellcheck source=/dev/null
source "$SHELL_COMMONS/permissions.sh"
# shellcheck source=/dev/null
source "$SHELL_COMMONS/strings.sh"

check_root
check_command "paru"

# Define the default zone; most systems use "public"
ZONE="public"
BRIDGE_IF="virbr0"
# 192.168.122.0/24 = The virtual network range where VMs live by default.
SUBNET="192.168.122.0/24"

print_status info "Checking to see if ufw is installed..."
if check_command "ufw"; then
  print_status error "ufw is installed. Aborting..."
  exit 1
fi

print_status info "Installing firewalld..."
paru -S --skipreview --noconfirm firewalld

print_status info ">> Enabling and starting firewalld..."
systemctl enable --now firewalld

print_status info "Allowing DHCP and DNS in zone: $ZONE..."
firewall-cmd --zone="$ZONE" --add-service=dhcp --permanent
firewall-cmd --zone="$ZONE" --add-service=dns --permanent

print_status info "Associating $BRIDGE_IF with zone: $ZONE..."
firewall-cmd --zone="$ZONE" --add-interface="$BRIDGE_IF" --permanent

print_status info "Enabling masquerading in zone: $ZONE..."
firewall-cmd --zone="$ZONE" --add-masquerade --permanent

print_status info "Enable http and https service in zone: $ZONE..."
firewall-cmd --permanent --zone="$ZONE" --add-service=http
firewall-cmd --permanent --zone="$ZONE" --add-service=https
firewall-cmd --reload

print_status info "Adding NAT rules for subnet $SUBNET..."
# This ensures forwarding from the VM subnet to external interfaces
firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -s "$SUBNET" -o "$(ip route | awk '/default/ {print $5; exit}')" -j MASQUERADE

print_status info "Reloading firewalld to apply changes..."
firewall-cmd --reload

print_status info "Firewalld configuration complete. Current zone status:"
firewall-cmd --zone="$ZONE" --list-all

print_status success "firewalld installed successfully."
