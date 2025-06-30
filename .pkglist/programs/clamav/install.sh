#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$SHELL_COMMONS/commands.sh"
source "$SHELL_COMMONS/permissions.sh"

check_root
check_command "paru"

CLAMAV_CONFIGS="$PROGRAMS/clamav/configs"
CLAMAV_SCRIPTS="$PROGRAMS/clamav/scripts"
CLAMAV_SERVICES="$PROGRAMS/clamav/services"

echo "🔧 Installing ClamAV and required tools..."
paru -S --skipreview --noconfirm clamav
"$SUDOU" "$SUDO_USER" -i paru -S --needed --skipreview --noconfirm clamav-unofficial-sigs

# Copy configs
echo "🔧 Copying configurations..."
chown root:root "$CLAMAV_CONFIGS/clamd.conf" && cp -f ./configs/clamd.conf /etc/clamav/clamd.conf
chown root:root "$CLAMAV_CONFIGS/freshclam.conf" && cp -f ./configs/freshclam.conf /etc/clamav/freshclam.conf
cp -f "$CLAMAV_CONFIGS/user.conf" /etc/clamav-unofficial-sigs/user.conf

# Copy services
echo "🔧 Copying services..."
chown root:root "$CLAMAV_SERVICES/clamav-clamonacc.service" && cp -f "$CLAMAV_SERVICES/clamav-clamonacc.service" /usr/lib/systemd/system/clamav-clamonacc.service

# Copy scripts
chmod +x "$CLAMAV_SCRIPTS/virus-event.sh" && cp -f "$CLAMAV_SCRIPTS/virus-event.sh" /etc/clamav/virus-event.sh

# Update virus database
echo "🔧 Updating virus definitions..."
freshclam

echo "🔧 Reloading systemd daemon..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload

# Enable services
echo "🔧 Enabling services..."
systemctl enable --now clamav-daemon.service
systemctl enable --now clamav-freshclam.service
systemctl enable --now clamav-clamonacc.service
systemctl enable --now clamav-unofficial-sigs.timer

echo "✅ ClamAV installed successfully."
