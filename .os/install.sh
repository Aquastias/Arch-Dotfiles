#!/usr/bin/env bash
# =============================================================================
# install.sh — single entry point for the Arch Linux ZFS installer
# =============================================================================
# Runs the three numbered scripts in order:
#   1. 01-bootstrap-zfs.sh — adds archzfs and loads ZFS modules on the live ISO
#   2. 02-wipe.sh          — wipes every detected disk (always run;
#                            not optional)
#   3. 03-install.sh       — partitions, pacstraps, configures, runs profiles
#
# The numbered scripts remain individually runnable for debugging. An optional
# positional argument is forwarded to 03-install.sh as an alternate config path.
# Recognised flags are stripped here and re-emitted to the numbered scripts.
#
# USAGE:
#   ./install.sh                           # uses install.jsonc next to this
#                                          # file
#   ./install.sh /path/to/install.jsonc    # alternate config
#   ./install.sh -y                        # unattended (no prompts)
#   ./install.sh --unattended /path/cfg    # unattended + alternate config
#
# OPTIONS:
#   -y, --unattended   Bypass every interactive confirmation prompt — disk
#                      exclusion, the WIPE confirmation, and the final
#                      "Proceed?" summary. Hostname must be set in the config
#                      beforehand; the hostname prompt is not bypassed.
#   -h, --help         Print this help and exit.
# =============================================================================

set -Eeuo pipefail
_install_on_err() {
  echo -e "\n\033[0;31m[install.sh]\033[0m aborted at line $1." >&2
}
trap '_install_on_err "$LINENO"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: ./install.sh [OPTIONS] [CONFIG_FILE]

Single entry point for the Arch Linux ZFS installer. Runs, in order:
  1. 01-bootstrap-zfs.sh
  2. 02-wipe.sh
  3. 03-install.sh [CONFIG_FILE]

Options:
  -y, --unattended   Bypass every interactive confirmation prompt (disk
                     exclusion, "WIPE" confirmation, final "Proceed?").
                     Hostname must be set in install.jsonc beforehand.
  -h, --help         Show this help and exit.
EOF
}

forward_args=()
positional_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y | --unattended)
      export INSTALL_UNATTENDED=1
      forward_args+=(--unattended)
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        positional_args+=("$1")
        shift
      done
      ;;
    -*)
      echo "[install.sh] Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      positional_args+=("$1")
      shift
      ;;
  esac
done

bash "${SCRIPT_DIR}/01-bootstrap-zfs.sh"
bash "${SCRIPT_DIR}/02-wipe.sh" "${forward_args[@]}"
bash "${SCRIPT_DIR}/03-install.sh" "${forward_args[@]}" "${positional_args[@]}"
