#!/usr/bin/env bash

set -euo pipefail
trap 'echo "Error on line $LINENO"' ERR

# shellcheck source=/dev/null
source "$SHELL_COMMONS/commands.sh"
source "$SHELL_COMMONS/permissions.sh"
source "$SHELL_COMMONS/strings.sh"

check_root
check_command "paru"

CLAMAV_CONFIGS="$PROGRAMS/clamav/configs"
CLAMAV_ENTRIES="$PROGRAMS/clamav/entries"
CLAMAV_SCRIPTS="$PROGRAMS/clamav/scripts"
CLAMAV_SERVICES="$PROGRAMS/clamav/services"

print_status info "Installing ClamAV and required tools..."
paru -S --skipreview --noconfirm clamav
"$SUDO" -u "$SUDO_USER" -i paru -S --needed --skipreview --noconfirm clamav-unofficial-sigs

# Copy configs
print_status info "Copying configurations..."
chown root:root "$CLAMAV_CONFIGS/clamd.conf" && cp -f ./configs/clamd.conf /etc/clamav/clamd.conf
chown root:root "$CLAMAV_CONFIGS/freshclam.conf" && cp -f ./configs/freshclam.conf /etc/clamav/freshclam.conf
cp -f "$CLAMAV_CONFIGS/user.conf" /etc/clamav-unofficial-sigs/user.conf

# Copy entries
print_status info "Copying entries..."
cp -f "$CLAMAV_ENTRIES/clamav.desktop" "/usr/share/applications"

# Copy services
print_status info "Copying services..."
chown root:root "$CLAMAV_SERVICES/clamav-clamonacc.service"
cp -f "$CLAMAV_SERVICES/clamav-clamonacc.service" /usr/lib/systemd/system/clamav-clamonacc.service

# Copy scripts
chmod +x "$CLAMAV_SCRIPTS/virus-event.sh" && cp -f "$CLAMAV_SCRIPTS/virus-event.sh" /etc/clamav/virus-event.sh

# Allow notify-send to be called by all users via sudo
SUDOERS_FILE="/etc/sudoers.d/clamav"
SUDOERS_LINE="clamav ALL = (ALL) NOPASSWD: SETENV: /usr/bin/notify-send"

print_status info "Ensuring sudoers rule exists in $SUDOERS_FILE..."

# Create the file if it doesn't exist
if [[ ! -f "$SUDOERS_FILE" ]]; then
  print_status info "File doesn't exist. Creating it..."
  echo "$SUDOERS_LINE" >"$SUDOERS_FILE"
  chmod 0440 "$SUDOERS_FILE"
elif ! grep -Fxq "$SUDOERS_LINE" "$SUDOERS_FILE"; then
  print_status info "Line not present. Appending to file..."
  echo "$SUDOERS_LINE" >>"$SUDOERS_FILE"
else
  print_status success "Sudoers line already exists. No changes made."
fi

# Validate the sudoers file
if visudo -c -f "$SUDOERS_FILE"; then
  print_status success "Sudoers file is valid."
else
  print_status error "Sudoers file is invalid! Removing..."
  rm -f "$SUDOERS_FILE"
  exit 1
fi

# Update virus database
print_status info "Updating virus definitions..."
freshclam

print_status info "Reloading systemd daemon..."
systemctl daemon-reexec
systemctl daemon-reload

# Enable services
print_status info "Enabling services..."

systemctl disable clamav-daemon.socket
systemctl disable clamav-daemon.service
systemctl disable clamav-freshclam.service
systemctl disable clamav-clamonacc.service
systemctl disable clamav-unofficial-sigs.timer
systemctl enable --now clamav-daemon.socket
systemctl enable --now clamav-daemon.service
systemctl enable --now clamav-freshclam.service
systemctl enable --now clamav-clamonacc.service
systemctl enable --now clamav-unofficial-sigs.timer

print_status success "ClamAV installed successfully."
