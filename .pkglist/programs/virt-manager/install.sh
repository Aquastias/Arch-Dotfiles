#!/usr/bin/env bash

set -euo pipefail
trap 'echo "Error on line $LINENO"' ERR

# shellcheck source=/dev/null
source "$SHELL_COMMONS/commands.sh"
source "$SHELL_COMMONS/permissions.sh"
source "$SHELL_COMMONS/strings.sh"

check_root
check_command "paru"

LIBVIRT_GROUP="libvirt"
QEMU_CONF="/etc/libvirt/qemu.conf"
POLKIT_RULE="/etc/polkit-1/rules.d/50-libvirt.rules"

print_status info "Installing virt-manager and required tools..."
paru -S --skipreview --noconfirm qemu-base virt-manager virt-viewer dnsmasq vde2 bridge-utils openbsd-netcat ebtables iptables-nft libguestfs edk2-ovmf

print_status info "Enabling libvirtd service..."
systemctl stop libvirtd-admin.socket
systemctl stop libvirtd.socket
systemctl stop libvirtd-ro.socket
systemctl stop libvirtd.service
systemctl disable libvirtd.service
systemctl enable --now libvirtd.service
systemctl start libvirtd-admin.socket
systemctl start libvirtd.socket
systemctl start libvirtd-ro.socket
print_status info "Service is now enabled!"

print_status info "Ensuring '$LIBVIRT_GROUP' group exists..."
getent group libvirt >/dev/null || groupadd "$LIBVIRT_GROUP"

print_status info "Adding user '$SUDO_USER' to $LIBVIRT_GROUP and kvm groups..."
usermod -aG "$LIBVIRT_GROUP" "$SUDO_USER"
usermod -aG kvm "$SUDO_USER"
print_status success "$SUDO_USER added to $LIBVIRT_GROUP and kvm groups."

print_status info "Editing /etc/libvirt/libvirtd.conf to set socket group and permissions..."
# Set 'unix_sock_group = "libvirt"' (uncomment or add if missing)
sed -i '/^#\?unix_sock_group *=/d' /etc/libvirt/libvirtd.conf
echo 'unix_sock_group = "libvirt"' | tee -a /etc/libvirt/libvirtd.conf >/dev/null
# Set 'unix_sock_rw_perms = "0770"' (uncomment or add if missing)
sed -i '/^#\?unix_sock_rw_perms *=/d' /etc/libvirt/libvirtd.conf
echo 'unix_sock_rw_perms = "0770"' | tee -a /etc/libvirt/libvirtd.conf >/dev/null
print_status success "Socket prepared."

print_status info "Editing qemu.conf to fix storage file permission issues..."
# Backup the config first
cp "$QEMU_CONF" "$QEMU_CONF.bak"

# Uncomment and set the user
sed -i '/^#user *=/d' "$QEMU_CONF"
sed -i '/^user *=/d' "$QEMU_CONF"
echo "user = \"$SUDO_USER\"" | tee -a "$QEMU_CONF" >/dev/null

# Uncomment and set the group
sed -i '/^#group *=/d' "$QEMU_CONF"
sed -i '/^group *=/d' "$QEMU_CONF"
echo "group = \"$LIBVIRT_GROUP\"" | tee -a "$QEMU_CONF" >/dev/null

print_status info "QEMU now runs as user '$SUDO_USER' and group 'libvirt'."
print_status success "Storage file access issues should be resolved."

print_status info "Restarting libvirtd to apply configuration changes..."
systemctl restart libvirtd

print_status info "Creating a polkit rule to allow users in the kvm group to manage libvirt without authentication..."
tee "$POLKIT_RULE" >/dev/null <<'EOF'
/* Allow users in kvm group to manage the libvirt daemon without authentication */
polkit.addRule(function(action, subject) {
    if (action.id == "org.libvirt.unix.manage" &&
        subject.isInGroup("kvm")) {
            return polkit.Result.YES;
    }
});
EOF
chown root:root "$POLKIT_RULE"
chmod 644 "$POLKIT_RULE"
print_status success "Polkit rule defined."

print_status info "Ensuring libvirt default network is defined..."
if ! virsh net-list --all | grep -q default; then
  print_status info "Defining default network..."
  virsh net-define /usr/share/libvirt/networks/default.xml
fi

print_status info "Enabling autostart for default network..."
virsh net-autostart default

print_status info "Starting default network if not already active..."
if ! virsh net-list | grep -q default; then
  virsh net-start default
else
  print_status info "Default network is already active."
fi
print_status success "Default network is online."

print_status success "virt-manager installed successfully."
