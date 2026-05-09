#!/usr/bin/env bash
# =============================================================================
# programs/virtualization/virt-manager/install.sh
# =============================================================================
# Invoked by .os/lib/profiles.sh inside arch-chroot, as the owning user, with
# OS_DIR, PROGRAMS, SHELL_COMMONS pre-exported and temp NOPASSWD sudo granted.
#
# Installs virt-manager + the QEMU/KVM stack via paru, configures libvirtd's
# unix socket group/perms, sets qemu.conf user/group to the invoking user,
# drops a polkit rule allowing the kvm group to manage libvirt without auth,
# and enables libvirtd. The default network is defined and set to autostart;
# net-start is deferred to first boot since libvirtd is not running inside
# the chroot.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[virt-manager] error on line $LINENO" >&2' ERR

LIBVIRT_GROUP="libvirt"
LIBVIRTD_CONF="/etc/libvirt/libvirtd.conf"
QEMU_CONF="/etc/libvirt/qemu.conf"
POLKIT_RULE="/etc/polkit-1/rules.d/50-libvirt.rules"

print_status info "Installing virt-manager and required tools..."
paru -S --noconfirm --needed \
  qemu-base virt-manager virt-viewer dnsmasq vde2 bridge-utils \
  openbsd-netcat ebtables iptables-nft libguestfs edk2-ovmf

print_status info "Enabling libvirtd service (starts on first boot)..."
sudo systemctl enable libvirtd.service

print_status info "Ensuring '$LIBVIRT_GROUP' group exists..."
getent group "$LIBVIRT_GROUP" >/dev/null || sudo groupadd "$LIBVIRT_GROUP"

print_status info "Configuring $LIBVIRTD_CONF socket group/perms..."
sudo sed -i '/^#\?unix_sock_group *=/d' "$LIBVIRTD_CONF"
echo 'unix_sock_group = "libvirt"' | sudo tee -a "$LIBVIRTD_CONF" >/dev/null
sudo sed -i '/^#\?unix_sock_rw_perms *=/d' "$LIBVIRTD_CONF"
echo 'unix_sock_rw_perms = "0770"' | sudo tee -a "$LIBVIRTD_CONF" >/dev/null

target_user="$(id -un)"

print_status info "Backing up and editing $QEMU_CONF (qemu user='$target_user')..."
sudo cp "$QEMU_CONF" "$QEMU_CONF.bak"
sudo sed -i '/^#\?user *=/d'  "$QEMU_CONF"
sudo sed -i '/^user *=/d'     "$QEMU_CONF"
sudo sed -i '/^#\?group *=/d' "$QEMU_CONF"
sudo sed -i '/^group *=/d'    "$QEMU_CONF"
echo "user = \"$target_user\""    | sudo tee -a "$QEMU_CONF" >/dev/null
echo "group = \"$LIBVIRT_GROUP\"" | sudo tee -a "$QEMU_CONF" >/dev/null

print_status info "Writing polkit rule at $POLKIT_RULE..."
sudo tee "$POLKIT_RULE" >/dev/null <<'EOF'
/* Allow users in kvm group to manage the libvirt daemon without authentication */
polkit.addRule(function(action, subject) {
    if (action.id == "org.libvirt.unix.manage" &&
        subject.isInGroup("kvm")) {
            return polkit.Result.YES;
    }
});
EOF
sudo chown root:root "$POLKIT_RULE"
sudo chmod 644 "$POLKIT_RULE"

print_status info "Defining default libvirt network (autostart on first boot)..."
DEFAULT_NET_XML="/etc/libvirt/qemu/networks/default.xml"
DEFAULT_NET_AUTOSTART="/etc/libvirt/qemu/networks/autostart/default.xml"
if [[ -f /usr/share/libvirt/networks/default.xml ]]; then
  sudo install -d -o root -g root -m 755 "$(dirname "$DEFAULT_NET_XML")" "$(dirname "$DEFAULT_NET_AUTOSTART")"
  sudo install -o root -g root -m 644 /usr/share/libvirt/networks/default.xml "$DEFAULT_NET_XML"
  sudo ln -sf "$DEFAULT_NET_XML" "$DEFAULT_NET_AUTOSTART"
fi

print_status success "virt-manager staged (libvirtd + default network start on first boot)."
