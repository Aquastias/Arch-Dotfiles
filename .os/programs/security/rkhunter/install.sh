#!/usr/bin/env bash
# =============================================================================
# programs/security/rkhunter/install.sh
# =============================================================================
# Invoked by .os/lib/profiles.sh inside arch-chroot, as the owning user, with
# OS_DIR, PROGRAMS, SHELL_COMMONS pre-exported and temp NOPASSWD sudo granted.
#
# Installs rkhunter + unhide via paru, drops the bundled rkhunter.conf,
# desktop entry, scan service+timer, and scan helper. Stages shell-stdlib.sh
# at a fixed system path so the timer-driven scan script can source it
# post-boot (where SHELL_COMMONS is no longer exported). Enables the timer
# (fires on first boot). Logrotate config is applied via the bundled helper.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[rkhunter] error on line $LINENO" >&2' ERR

RKHUNTER_CONFIGS="${PROGRAMS}/security/rkhunter/configs"
RKHUNTER_ENTRIES="${PROGRAMS}/security/rkhunter/entries"
RKHUNTER_SCRIPTS="${PROGRAMS}/security/rkhunter/scripts"
RKHUNTER_SERVICES="${PROGRAMS}/security/rkhunter/services"

print_status info "Installing rkhunter and required tools..."
paru -S --noconfirm --needed rkhunter unhide

print_status info "Updating rkhunter malware database..."
sudo rkhunter --update || true

print_status info "Building file properties baseline..."
sudo rkhunter --propupd

print_status info "Copying configurations..."
sudo install -o root -g root -m 644 "$RKHUNTER_CONFIGS/rkhunter.conf" /etc/rkhunter.conf

print_status info "Copying entries..."
sudo install -o root -g root -m 644 "$RKHUNTER_ENTRIES/rkhunter.desktop" /usr/share/applications/rkhunter.desktop

print_status info "Copying services..."
sudo install -o root -g root -m 644 "$RKHUNTER_SERVICES/rkhunter-scan.service" /usr/lib/systemd/system/rkhunter-scan.service
sudo install -o root -g root -m 644 "$RKHUNTER_SERVICES/rkhunter-scan.timer"   /usr/lib/systemd/system/rkhunter-scan.timer

# Stage shell-stdlib.sh for post-boot use by rkhunter_scan.sh. The runtime
# script sources from this fixed path because $SHELL_COMMONS is only set
# during install.
print_status info "Staging shell-stdlib.sh at /usr/local/lib/shell-stdlib.sh..."
sudo install -d -o root -g root -m 755 /usr/local/lib /usr/local/lib/rkhunter
sudo install -o root -g root -m 644 "${SHELL_COMMONS}/shell-stdlib.sh"        /usr/local/lib/shell-stdlib.sh
sudo install -o root -g root -m 755 "$RKHUNTER_SCRIPTS/rkhunter_scan.sh"      /usr/local/lib/rkhunter/rkhunter_scan.sh

print_status info "Enabling rkhunter-scan.timer (fires on first boot)..."
sudo systemctl enable rkhunter-scan.timer

print_status info "Applying logrotate config..."
sudo SHELL_COMMONS="${SHELL_COMMONS}" "$RKHUNTER_SCRIPTS/rkhunter_logrotate.sh"

print_status success "RKHunter staged."
