#!/usr/bin/env bash

set -euo pipefail
trap 'echo "Error on line $LINENO"' ERR

# shellcheck source=/dev/null
source "$SHELL_COMMONS/commands.sh"
source "$SHELL_COMMONS/permissions.sh"
source "$SHELL_COMMONS/strings.sh"

check_root
check_command "paru"

RKHUNTER_CONFIGS="$PROGRAMS/rkhunter/configs"
RKHUNTER_ENTRIES="$PROGRAMS/rkhunter/entries"
RKHUNTER_SCRIPTS="$PROGRAMS/rkhunter/scripts"
RKHUNTER_SERVICES="$PROGRAMS/rkhunter/services"

print_status info "Installing ClamAV and required tools..."
paru -S --skipreview --noconfirm rkhunter unhide

# Copy configs
print_status info "Copying configurations..."
chown root:root "$RKHUNTER_CONFIGS/rkhunter.conf" && cp -f ./configs/rkhunter.conf /etc/rkhunter.conf

# Copy entries
print_status info "Copying entries..."
cp -f "$RKHUNTER_ENTRIES/rkhunter.desktop" "/usr/share/applications"

# Copy services
print_status info "Copying services..."
chown root:root "$RKHUNTER_SERVICES/rkhunter-scan.service"
chown root:root "$RKHUNTER_SERVICES/rkhunter-scan.timer"
cp -f "$RKHUNTER_SERVICES/rkhunter-scan.service" /usr/lib/systemd/system/rkhunter-scan.service
cp -f "$RKHUNTER_SERVICES/rkhunter-scan.timer" /usr/lib/systemd/system/rkhunter-scan.service

# Copy scripts
mkdir -p /usr/local/lib/rkhunter
chmod +x "$RKHUNTER_SCRIPTS/rkhunter_scan.sh"
cp -f "$RKHUNTER_SCRIPTS/rkhunter_scan.sh" /usr/local/lib/rkhunter/rkhunter_scan.sh
chown root:root /usr/local/lib/rkhunter/rkhunter_scan.sh

# Enable services
print_status info "Reloading systemd daemon..."
systemctl daemon-reexec
systemctl daemon-reload

print_status info "Enabling services..."
systemctl disable rkhunter-scan.timer
systemctl enable --now rkhunter-scan.timer

# Enable logrotate
LOGROTATE_SCRIPT="$RKHUNTER_SCRIPTS/rkhunter_logrotate.sh"
make_executable_and_run "$LOGROTATE_SCRIPT"

print_status success "RKHunter installed successfully."
