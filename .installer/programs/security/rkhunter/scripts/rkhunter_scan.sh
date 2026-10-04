#!/usr/bin/env bash

set -euo pipefail
trap 'echo "Error on line $LINENO"' ERR

# Sourced from a fixed system path: install.sh stages shell-stdlib.sh here
# because this script runs from a systemd timer post-boot, where $SHELL_COMMONS
# is no longer exported.
# shellcheck source=/dev/null
source "/usr/local/lib/shell-stdlib.sh"

check_root

SYSTEM_LOG="/var/log/rkhunter.log"

echo "=== RKHunter Desktop Scan: $(date) ===" | tee -a "$SYSTEM_LOG"

# Update definitions, then the database. --update exits 2 when it installed
# updates and 1 on a download error (rkhunter(8)); neither may stop the
# scan, so an offline machine still scans on the data it has.
rc=0
rkhunter --update --nocolors >>"$SYSTEM_LOG" 2>&1 || rc=$?
if (( rc == 1 )); then
  echo "rkhunter --update: download failed; scanning on existing data." \
    | tee -a "$SYSTEM_LOG"
elif (( rc > 2 )); then
  echo "rkhunter --update failed (exit $rc)." | tee -a "$SYSTEM_LOG"
  exit "$rc"
fi
rkhunter --propupd -q >>"$SYSTEM_LOG" 2>&1

# Run the scan
{ rkhunter --check --sk --nocolors --quiet 2>&1 \
    | grep -v -e 'egrep: warning' -e 'grep: warning' \
    || true; } | tee -a "$SYSTEM_LOG"

# Check for warnings
WARNINGS=$(grep "Warning:" "$SYSTEM_LOG" || true)

if [ -n "$WARNINGS" ]; then
  print_status warning "RKHunter found warnings!" | tee -a "$SYSTEM_LOG"
  send_user_notification \
    "Warnings detected!" \
    "Check $SYSTEM_LOG" \
    "security-medium" \
    "RKHunter Scan" \
    15000 \
    "rkhunter"
else
  print_status success "No warnings found." | tee -a "$SYSTEM_LOG"
  send_user_notification \
    "RKHunter Scan Complete" \
    "No warnings found." \
    "security-high" \
    "RKHunter Scan" \
    15000 \
    "rkhunter"
fi
