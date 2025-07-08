#!/usr/bin/env bash

set -euo pipefail
trap 'echo "Error on line $LINENO"' ERR

# shellcheck source=/dev/null
source "$SHELL_COMMONS/permissions.sh"
source "$SHELL_COMMONS/strings.sh"

check_root

SYSTEM_LOG="/var/log/rkhunter.log"

echo "=== RKHunter Desktop Scan: $(date) ===" | tee -a "$SYSTEM_LOG"

# Update definitions and database
rkhunter --update >>"$SYSTEM_LOG" 2>&1
rkhunter --propupd -q >>"$SYSTEM_LOG" 2>&1

# Run the scan
{ rkhunter --check --sk --nocolors --quiet 2>&1 | grep -v -e 'egrep: warning' -e 'grep: warning' || true; } | tee -a "$SYSTEM_LOG"

# Check for warnings
WARNINGS=$(grep "Warning:" "$SYSTEM_LOG" || true)

if [ -n "$WARNINGS" ]; then
  print_status warning "RKHunter found warnings!" | tee -a "$SYSTEM_LOG"
  "$SUDO" -u "$SUDO_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus notify-send -a "RKHunter Scan" \
    -h "string:desktop-entry:rkhunter" \
    -t 15000 \
    -i "security-medium" \
    "Warnings detected!" \
    "Check $SYSTEM_LOG"
else
  print_status success "No warnings found." | tee -a "$SYSTEM_LOG"
  "$SUDO" -u "$SUDO_USER" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus notify-send -a "RKHunter Scan" \
    -h "string:desktop-entry:rkhunter" \
    -t 15000 \
    -i "security-high" \
    "RKHunter Scan Complete" \
    "No warnings found."
fi
