#!/usr/bin/env bash

set -euo pipefail
trap 'echo "Error on line $LINENO"' ERR

# shellcheck source=/dev/null
source "$SHELL_COMMONS/commands.sh"
source "$SHELL_COMMONS/permissions.sh"
source "$SHELL_COMMONS/strings.sh"

check_root
check_command "paru"

# Define the default zone; most systems use "public"
ZONE="public"
BRIDGE_IF="virbr0"

print_status info "Installing firewalld..."
paru -S --skipreview --noconfirm firewalld

print_status info ">> Enabling and starting firewalld..."
systemctl enable --now firewalld

print_status info "Allowing DHCP and DNS in zone: $ZONE..."
firewall-cmd --zone="$ZONE" --add-service=dhcp --permanent
firewall-cmd --zone="$ZONE" --add-service=dns --permanent

print_status info "Associating $BRIDGE_IF with zone: $ZONE..."
firewall-cmd --zone="$ZONE" --add-interface="$BRIDGE_IF" --permanent

print_status info "Reloading firewalld to apply changes..."
firewall-cmd --reload

print_status info "Firewalld configuration complete. Current zone status:"
firewall-cmd --zone="$ZONE" --list-all

print_status success "firewalld installed successfully."
