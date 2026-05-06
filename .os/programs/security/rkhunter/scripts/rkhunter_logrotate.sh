#!/usr/bin/env bash

set -euo pipefail
trap 'echo "Error on line $LINENO"' ERR

# Invoked by install.sh via sudo (root). logrotate is in the official
# extra repo, so pacman is enough — no paru needed.

# shellcheck source=/dev/null
source "$SHELL_COMMONS/shell-stdlib.sh"

check_root

LOGROTATE_CONF="/etc/logrotate.d/rkhunter"

print_status info "Setting up log rotation for RKHunter..."

cat <<CFG >"$LOGROTATE_CONF"
/var/log/rkhunter.log {
  daily
  rotate 7
  compress
  missingok
  notifempty
  create 640 root adm
}
CFG

chmod 644 "$LOGROTATE_CONF"
print_status info "Logrotate configuration created at: $LOGROTATE_CONF"

print_status info "Testing logrotate configuration..."
if ! command_exists logrotate; then
  pacman -S --noconfirm --needed logrotate
fi
logrotate -d "$LOGROTATE_CONF" 2>&1 | grep -v 'logrotate in debug mode does nothing'

print_status success "Log rotation activated!"
