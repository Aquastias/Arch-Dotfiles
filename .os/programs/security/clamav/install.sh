#!/usr/bin/env bash
# =============================================================================
# programs/security/clamav/install.sh
# =============================================================================
# Invoked by .os/lib/profiles/runner.sh inside arch-chroot, as the owning user, with
# OS_DIR, PROGRAMS, SHELL_COMMONS pre-exported and temp NOPASSWD sudo granted.
#
# Installs clamav via paru, drops bundled configs into /etc/clamav, installs
# the desktop entry, the on-access systemd unit, the daily-scan timer +
# helper, the virus-event hook, and a sudoers drop-in for notify-send.
#
# Stages shell-stdlib.sh and clamav_exclude_list.json under /usr/local/lib/
# so the daily-scan timer can run post-boot without $SHELL_COMMONS.
# clamav-unofficial-sigs is also pulled via paru.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[clamav] error on line $LINENO" >&2' ERR

CLAMAV_PROG_DIR="${PROGRAMS}/security/clamav"
CLAMAV_INSTALL="${CLAMAV_PROG_DIR}/install"
CLAMAV_ENTRIES="${CLAMAV_PROG_DIR}/entries"
CLAMAV_SCRIPTS="${CLAMAV_PROG_DIR}/scripts"
CLAMAV_SERVICES="${CLAMAV_PROG_DIR}/services"

print_status info "Installing ClamAV + clamav-unofficial-sigs..."
paru -S --noconfirm --needed clamav clamav-unofficial-sigs

print_status info "Copying configurations..."
sudo install -o root -g root -m 644 \
  "$CLAMAV_INSTALL/clamd.conf" /etc/clamav/clamd.conf
sudo install -o root -g root -m 644 \
  "$CLAMAV_INSTALL/freshclam.conf" /etc/clamav/freshclam.conf
sudo install -d -o root -g root -m 755 /etc/clamav-unofficial-sigs
sudo install -o root -g root -m 644 \
  "$CLAMAV_INSTALL/user.conf" /etc/clamav-unofficial-sigs/user.conf

print_status info "Copying entries..."
sudo install -o root -g root -m 644 \
  "$CLAMAV_ENTRIES/clamav.desktop" /usr/share/applications/clamav.desktop

print_status info "Copying services..."
sudo install -o root -g root -m 644 \
  "$CLAMAV_SERVICES/clamav-clamonacc.service" \
  /usr/lib/systemd/system/clamav-clamonacc.service
sudo install -o root -g root -m 644 \
  "$CLAMAV_SERVICES/clamav-daily-scan.service" \
  /usr/lib/systemd/system/clamav-daily-scan.service
sudo install -o root -g root -m 644 \
  "$CLAMAV_SERVICES/clamav-daily-scan.timer" \
  /usr/lib/systemd/system/clamav-daily-scan.timer

# Stage shell-stdlib.sh + exclude list + daily-scan helper for the timer.
# These run post-boot, where $SHELL_COMMONS / $PROGRAMS are no longer set.
print_status info "Staging shell-stdlib.sh and daily-scan helper" \
  "under /usr/local/lib..."
sudo install -d -o root -g root -m 755 /usr/local/lib /usr/local/lib/clamav
sudo install -o root -g root -m 644 \
  "${SHELL_COMMONS}/shell-stdlib.sh" /usr/local/lib/shell-stdlib.sh
sudo install -o root -g root -m 644 \
  "$CLAMAV_PROG_DIR/clamav_exclude_list.json" \
  /usr/local/lib/clamav/clamav_exclude_list.json
sudo install -o root -g root -m 755 \
  "$CLAMAV_SCRIPTS/clamav_daily_scan.sh" \
  /usr/local/lib/clamav/clamav_daily_scan.sh

print_status info "Installing virus-event hook..."
sudo install -o root -g root -m 755 \
  "$CLAMAV_SCRIPTS/virus-event.sh" /etc/clamav/virus-event.sh

SUDOERS_FILE="/etc/sudoers.d/clamav"
SUDOERS_LINE="clamav ALL = (ALL) NOPASSWD: SETENV: /usr/bin/notify-send"

print_status info "Ensuring sudoers rule exists in $SUDOERS_FILE..."
if ! sudo test -f "$SUDOERS_FILE"; then
  printf '%s\n' "$SUDOERS_LINE" | sudo tee "$SUDOERS_FILE" >/dev/null
  sudo chmod 0440 "$SUDOERS_FILE"
elif ! sudo grep -Fxq "$SUDOERS_LINE" "$SUDOERS_FILE"; then
  printf '%s\n' "$SUDOERS_LINE" | sudo tee -a "$SUDOERS_FILE" >/dev/null
fi

if sudo visudo -c -f "$SUDOERS_FILE"; then
  print_status success "Sudoers file is valid."
else
  print_status error "Sudoers file is invalid! Removing..."
  sudo rm -f "$SUDOERS_FILE"
  exit 1
fi

print_status info "Enabling services (started on first boot)..."
sudo systemctl enable clamav-daemon.service
sudo systemctl enable clamav-freshclam.service
sudo systemctl enable clamav-clamonacc.service
sudo systemctl enable clamav-daily-scan.timer

print_status success "ClamAV staged."
