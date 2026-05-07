#!/usr/bin/env bash
# =============================================================================
# programs/security/ufw/install.sh
# =============================================================================
# Invoked by .os/lib/profiles.sh inside arch-chroot, as the owning user, with
# OS_DIR, PROGRAMS, SHELL_COMMONS pre-exported and temp NOPASSWD sudo granted.
#
# Installs ufw via paru and seeds default policies + libvirt bridge rules +
# NAT masquerading. Aborts if firewalld is installed (mutually exclusive).
# =============================================================================

set -Eeuo pipefail
trap 'echo "[ufw] error on line $LINENO" >&2' ERR

if check_command "firewall-cmd" || package_installed "firewalld"; then
  print_status error "firewalld is installed; firewalld and ufw cannot coexist."
  exit 1
fi

print_status info "Installing UFW..."
paru -S --noconfirm --needed --skipreview ufw

print_status info "Resetting UFW to defaults..."
sudo ufw --force reset

print_status info "Setting default policy: deny incoming, allow outgoing..."
sudo ufw default deny incoming
sudo ufw default allow outgoing

print_status info "Adding rules for libvirt (DHCP, DNS, virbr0 bridge)..."
sudo ufw allow out 67,68/udp comment 'Allow DHCP for VMs'
sudo ufw allow out 53/udp    comment 'Allow DNS for VMs'
sudo ufw allow in on virbr0  comment 'Allow incoming VM traffic'
sudo ufw allow out on virbr0 comment 'Allow outgoing VM traffic'
sudo ufw allow http
sudo ufw allow https

print_status info "Adding NAT masquerading for libvirt VMs..."

# External interface detection only works in a booted system; fall back to a
# known-good default for the chroot phase. Override via UFW_EXT_IF env var.
EXT_IF="${UFW_EXT_IF:-}"
if [[ -z "$EXT_IF" ]]; then
  if command -v ip &>/dev/null; then
    EXT_IF="$(ip route show default 0.0.0.0/0 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')"
  fi
fi
if [[ -z "$EXT_IF" ]]; then
  print_status warning "Could not detect external NIC; defaulting to eth0. Set UFW_EXT_IF to override."
  EXT_IF="eth0"
fi

BEFORE_RULES="/etc/ufw/before.rules"
if ! sudo test -f "${BEFORE_RULES}.bak"; then
  sudo cp "$BEFORE_RULES" "${BEFORE_RULES}.bak"
fi

if ! sudo grep -q 'POSTROUTING -s 192.168.122.0/24 -o' "$BEFORE_RULES"; then
  sudo sed -i '/^\*filter/i \
# NAT table rules for libvirt VMs\n\
*nat\n\
:POSTROUTING ACCEPT [0:0]\n\
-A POSTROUTING -s 192.168.122.0/24 -o '"$EXT_IF"' -j MASQUERADE\n\
COMMIT\n' "$BEFORE_RULES"
  print_status success "NAT masquerade rules added to $BEFORE_RULES"
else
  print_status info "NAT masquerade rules already exist in $BEFORE_RULES"
fi

print_status info "Enabling UFW service (rules apply on first boot)..."
sudo ufw --force enable
sudo systemctl enable ufw.service

print_status success "UFW staged."
