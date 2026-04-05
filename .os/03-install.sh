#!/usr/bin/env bash
# =============================================================================
# 03-install.sh — Arch Linux ZFS Installer (orchestrator)
# =============================================================================
# RUN ORDER:
#   1. 01-bootstrap-zfs.sh   — prepares ZFS on the Arch live ISO
#   2. 02-wipe.sh            — (optional) full disk wipe
#   3. 03-install.sh         — this script
#
# USAGE:
#   ./03-install.sh                    # uses install.json in same directory
#   ./03-install.sh /path/to/cfg.json  # specify a different config file
#
# If install.json is missing, a documented template is generated and the
# script exits so you can edit it before re-running.
#
# This script is intentionally thin — it only sets up global constants,
# sources the lib/ modules, and defines main(). All logic lives in lib/.
#
# MODULE LOAD ORDER (each module declares its own functions and globals):
#   lib/common.sh        — colours, output helpers, cfg/cfgo, shared globals
#   lib/config.sh        — template generation, load/validate config, mode
#                          detection, installation summary
#   lib/zfs-pools.sh     — ZFS tool fallback, encryption opts, pool creation
#                          helper, OS dataset creation, vdev spec builder
#   lib/layout-single.sh — single-disk sizing, partitioning, pool creation,
#                          ESP mounting
#   lib/layout-multi.sh  — multi-disk topology resolution, partitioning,
#                          pool creation, ESP mounting
#   lib/packages.sh      — package collection, pacstrap
#   lib/chroot.sh        — fstab, ESP mirror hook, arch-chroot configuration
#   lib/finalize.sh      — unmount, pool export, completion summary
# =============================================================================

set -Eeuo pipefail
trap '_on_error $LINENO' ERR
_on_error() {
  # Colours may not be loaded yet if the error is very early, so use raw codes
  echo -e "\n\033[0;31m[ERROR]\033[0m Installer failed at line $1." >&2
  echo -e "\033[2mCheck the output above for details.\033[0m" >&2
  exit 1
}

# =============================================================================
# GLOBAL CONSTANTS — set before sourcing any module
# =============================================================================

# Absolute path to the directory containing this script.
# All lib/ paths and the default config path are relative to this.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Path to the JSON config file. Can be overridden via command-line argument.
CONFIG_FILE="${1:-${SCRIPT_DIR}/install.json}"

# Mountpoint for the new system during installation.
MOUNT_ROOT="/mnt"

# =============================================================================
# SOURCE ALL MODULES
# =============================================================================

source_module() {
  local path="$1"
  [[ -f "$path" ]] || {
    echo -e "\033[0;31m[ERROR]\033[0m Required module not found: $path" >&2
    exit 1
  }
  # shellcheck source=/dev/null
  source "$path"
}

source_module "${SCRIPT_DIR}/lib/common.sh"
source_module "${SCRIPT_DIR}/lib/config.sh"
source_module "${SCRIPT_DIR}/lib/zfs-pools.sh"
source_module "${SCRIPT_DIR}/lib/layout-single.sh"
source_module "${SCRIPT_DIR}/lib/layout-multi.sh"
source_module "${SCRIPT_DIR}/lib/packages.sh"
source_module "${SCRIPT_DIR}/lib/chroot.sh"
source_module "${SCRIPT_DIR}/lib/finalize.sh"

# =============================================================================
# MAIN
# =============================================================================

main() {
  echo -e "\n${CYAN}${BOLD}  Arch Linux ZFS Installer${NC}"
  echo -e "${DIM}  ─────────────────────────────────────────────────${NC}"
  echo -e "${DIM}  Config : ${CONFIG_FILE}${NC}"
  echo -e "${DIM}  Modules: ${SCRIPT_DIR}/lib/${NC}\n"

  # ── Pre-flight checks ─────────────────────────────────────────────────────
  [[ $EUID -eq 0 ]] || error "Run as root (sudo -i)."
  [[ -d /sys/firmware/efi ]] || error "Not in UEFI mode. Reboot and select a UEFI entry."

  # Install jq only if missing — skip the slow pacman -Sy if already present
  if ! command -v jq &>/dev/null; then
    info "Installing jq..."
    pacman -S --noconfirm --needed jq || error "Failed to install jq. Run 01-bootstrap-zfs.sh first."
  fi

  # Quick connectivity check via TCP (faster than ping, works through more firewalls)
  # Uses /dev/tcp which is built into bash — zero external dependencies
  if ! timeout 5 bash -c 'cat < /dev/null > /dev/tcp/archlinux.org/80' 2>/dev/null; then
    error "No internet connection. Required for pacstrap.
  Check: ip route show default   (needs a default gateway)
  Check: ping 8.8.8.8            (basic connectivity)"
  fi

  # ── Config phase ──────────────────────────────────────────────────────────
  load_config
  detect_mode
  validate_config

  # ── Interactive topology resolution (before any disk writes) ──────────────
  if [[ "$INSTALL_MODE" == "single" ]]; then
    calculate_single_disk_layout
  else
    resolve_os_topology
    resolve_storage_topologies
  fi

  # ── Final confirmation (shows full plan, asks user to proceed) ────────────
  print_summary

  # ── Collect encryption passphrase before any disk writes ─────────────────
  # Must run after confirmation (user has committed) but before pool creation.
  # Collects once; piped to every zpool create call so all pools share one key.
  collect_enc_passphrase

  # ── Disk operations ───────────────────────────────────────────────────────
  if [[ "$INSTALL_MODE" == "single" ]]; then
    partition_single_disk
    install_zfs_tools_if_needed
    create_single_pools
    mount_single_esp
  else
    partition_os_disks_multi
    partition_storage_disks_multi
    install_zfs_tools_if_needed
    create_multi_rpool
    create_multi_dpool
    mount_multi_esps
  fi

  # ── Install & configure ───────────────────────────────────────────────────
  install_base
  configure_system

  # ── Cleanup ───────────────────────────────────────────────────────────────
  finalize
}

main "$@"ain "$@"
