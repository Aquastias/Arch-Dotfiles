#!/usr/bin/env bash

set -euo pipefail
trap 'echo "Error on line $LINENO"' ERR

# shellcheck source=/dev/null
source "$SHELL_COMMONS/commands.sh"
source "$SHELL_COMMONS/permissions.sh"
source "$SHELL_COMMONS/strings.sh"

check_root
check_command "paru"

LOGROTATE_CONF="/etc/logrotate.d/rkhunter"

print_status info "Setting up log rotation for RKHunter..."

cat <<EOF >"$LOGROTATE_CONF"
/var/log/rkhunter.log {
  daily
  rotate 7
  compress
  missingok
  notifempty
  create 640 root adm
}
EOF

chmod 644 "$LOGROTATE_CONF"
print_status info "Logrotate configuration created at: $LOGROTATE_CONF"

# Optional: test logrotate config
print_status info "Testing logrotate configuration..."

if ! command_exists logrotate; then
  paru -S --skipreview --noconfirm logrotate
  logrotate -d "$LOGROTATE_CONF" 2>&1 | grep -v 'logrotate in debug mode does nothing'
else
  logrotate -d "$LOGROTATE_CONF" 2>&1 | grep -v 'logrotate in debug mode does nothing'
fi

print_status success "Log rotation activated!"
