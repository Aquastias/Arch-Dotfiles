#!/usr/bin/env bash
# =============================================================================
# shell-stdlib.sh — unified shell utility library (facade)
# =============================================================================
# Sources all domain modules from lib/shell/. Program Install Scripts source
# this file once via $SHELL_COMMONS/shell-stdlib.sh; all functions are then
# available without per-script source lines.
#
# To use a domain directly (e.g. in tests or standalone scripts):
#   source "$SHELL_COMMONS/shell/strings.sh"
# =============================================================================

_STDLIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/shell" && pwd)"

# shellcheck source=./shell/strings.sh
source "${_STDLIB_DIR}/strings.sh"
# shellcheck source=./shell/output.sh
source "${_STDLIB_DIR}/output.sh"
# shellcheck source=./shell/arrays.sh
source "${_STDLIB_DIR}/arrays.sh"
# shellcheck source=./shell/commands.sh
source "${_STDLIB_DIR}/commands.sh"
# shellcheck source=./shell/permissions.sh
source "${_STDLIB_DIR}/permissions.sh"
# shellcheck source=./shell/directories.sh
source "${_STDLIB_DIR}/directories.sh"
# shellcheck source=./shell/environments.sh
source "${_STDLIB_DIR}/environments.sh"
# shellcheck source=./shell/packages.sh
source "${_STDLIB_DIR}/packages.sh"
# shellcheck source=./shell/notifications.sh
source "${_STDLIB_DIR}/notifications.sh"

unset _STDLIB_DIR
