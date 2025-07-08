#!/usr/bin/env bash

set -euo pipefail
trap 'echo "Error on line $LINENO"' ERR

# shellcheck source=/dev/null
source "$SHELL_COMMONS/permissions.sh"
source "$SHELL_COMMONS/strings.sh"

check_root

# Use custom config file path if defined, otherwise default to /etc/sysctl.conf
CONF_FILE="${CONF_FILE:-/etc/sysctl.conf}"
SW_VALUE=10

# Backup the current config file
cp "$CONF_FILE" "${CONF_FILE}.bak.$(date +%F-%T)"

# Update or append the swappiness setting
if grep -q "^vm.swappiness" "$CONF_FILE"; then
  sed -i "s/^vm\.swappiness.*/vm.swappiness = $SW_VALUE/" "$CONF_FILE"
else
  echo "vm.swappiness = $SW_VALUE" >>"$CONF_FILE"
fi

print_status success "Swappiness set to $SW_VALUE and configured in: $CONF_FILE"
