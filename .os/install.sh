#!/usr/bin/env bash
# =============================================================================
# install.sh — single entry point for the Arch Linux ZFS installer
# =============================================================================
# Runs the three numbered scripts in order:
#   1. 01-bootstrap-zfs.sh — adds archzfs and loads ZFS modules on the live ISO
#   2. 02-wipe.sh          — wipes only the install's target disks, resolved
#                            from the config and passed explicitly
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
#                      selection, the WIPE confirmation, and the final
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

# Target Resolver — used to scope the wipe to the install's target disks.
# shellcheck source=lib/wipe/targets.sh
source "${SCRIPT_DIR}/lib/wipe/targets.sh"

usage() {
  cat <<'EOF'
Usage: ./install.sh [OPTIONS] [CONFIG_FILE]

Single entry point for the Arch Linux ZFS installer. Runs, in order:
  1. 01-bootstrap-zfs.sh
  2. 02-wipe.sh
  3. 03-install.sh [CONFIG_FILE]

Options:
  -y, --unattended   Bypass every interactive confirmation prompt (disk
                     selection, "WIPE" confirmation, final "Proceed?").
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

# Resolve the install's target disks from the config (single .disk, or multi
# os_pool/storage_groups/data_pools) so the wipe only ever touches disks this
# install will use. Mirrors 03-install.sh's config-path default. A missing
# config yields no targets — the wipe no-ops and 03 generates the template.
CONFIG_FILE="${positional_args[0]:-${SCRIPT_DIR}/install.jsonc}"
wipe_targets=()
if [[ -f "$CONFIG_FILE" ]]; then
  mapfile -t wipe_targets < <(wipe_resolve_targets "$CONFIG_FILE")
fi

bash "${SCRIPT_DIR}/01-bootstrap-zfs.sh"
bash "${SCRIPT_DIR}/02-wipe.sh" "${forward_args[@]}" "${wipe_targets[@]}"
bash "${SCRIPT_DIR}/03-install.sh" "${forward_args[@]}" "${positional_args[@]}"
