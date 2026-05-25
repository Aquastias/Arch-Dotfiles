#!/usr/bin/env bash
# =============================================================================
# programs/security/sops/install.sh
# =============================================================================
# Invoked by .os/lib/profiles.sh inside arch-chroot, as root.
# Env vars provided by the runner: OS_DIR, PROGRAMS, SHELL_COMMONS.
#
# Installs sops + ssh-to-age, derives the Machine Age Key from the SSH host
# key, and installs + enables the sops-runtime.service that decrypts
# /etc/secrets/sops/*.json to /run/secrets/ on every boot.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[sops] error on line $LINENO" >&2' ERR

SOPS_SERVICES="${PROGRAMS}/security/sops/services"
SOPS_SCRIPTS="${PROGRAMS}/security/sops/scripts"

print_status info "Installing sops..."
pacman -S --noconfirm --needed sops

# ssh-to-age has no Arch package; build from upstream via go.
print_status info "Building ssh-to-age from source..."
pacman -S --noconfirm --needed go
GOBIN=/usr/local/bin go install \
  github.com/Mic92/ssh-to-age/cmd/...@latest

print_status info "Ensuring SSH host key exists..."
pacman -S --noconfirm --needed openssh
[[ -f /etc/ssh/ssh_host_ed25519_key ]] || ssh-keygen -A

print_status info "Deriving Machine Age Key from SSH host key..."
mkdir -p /etc/secrets/age
ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key \
  > /etc/secrets/age/keys.txt
chmod 600 /etc/secrets/age/keys.txt
chown root:root /etc/secrets/age/keys.txt

print_status info "Installing sops-runtime script and service..."
install -d -o root -g root -m 755 /usr/local/lib/sops
install -o root -g root -m 755 \
  "$SOPS_SCRIPTS/sops-runtime.sh" /usr/local/lib/sops/sops-runtime.sh
install -o root -g root -m 644 \
  "$SOPS_SERVICES/sops-runtime.service" \
  /usr/lib/systemd/system/sops-runtime.service

print_status info "Enabling sops-runtime.service..."
systemctl enable sops-runtime.service

print_status success "SOPS runtime staged."
