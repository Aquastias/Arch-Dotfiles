#!/usr/bin/env bash
# =============================================================================
# install.sh — single entry point for the Arch Linux ZFS installer
# =============================================================================
# Runs the three numbered scripts in order:
#   1. 01-bootstrap-zfs.sh — adds archzfs and loads ZFS modules on the live ISO
#   2. 02-wipe.sh          — wipes every detected disk (always run; not optional)
#   3. 03-install.sh       — partitions, pacstraps, configures, runs profiles
#
# The numbered scripts remain individually runnable for debugging.
# Any optional argument is forwarded to 03-install.sh (alternate config path).
#
# USAGE:
#   ./install.sh                         # uses install.jsonc next to this file
#   ./install.sh /path/to/install.jsonc  # alternate config
# =============================================================================

set -Eeuo pipefail
trap 'echo -e "\n\033[0;31m[install.sh]\033[0m aborted at line $LINENO." >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "${SCRIPT_DIR}/01-bootstrap-zfs.sh"
bash "${SCRIPT_DIR}/02-wipe.sh"
bash "${SCRIPT_DIR}/03-install.sh" "$@"
