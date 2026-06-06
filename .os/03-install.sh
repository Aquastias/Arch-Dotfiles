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
#   ./03-install.sh                          # uses install.jsonc in same dir
#   ./03-install.sh /path/to/cfg.jsonc       # alternate config path
#   ./03-install.sh -y                       # unattended (skip "Proceed?")
#   ./03-install.sh --unattended /path/cfg   # unattended + alternate config
#
# Honors INSTALL_UNATTENDED=1 from the environment as well as the CLI flag.
#
# If install.json is missing, a documented template is generated and the
# script exits so you can edit it before re-running.
#
# This script is intentionally thin — it only sets up global constants,
# sources the lib/ modules, and defines main(). All logic lives in lib/.
#
# MODULE LOAD ORDER (each module declares its own functions and globals):
#   lib/common.sh        — colours, output helpers, cfg/cfgo, part_name,
#                          shared globals
#   lib/config/lifecycle.sh        — template generation, load/validate config, mode
#                          detection, installation summary
#   lib/zfs/pools.sh     — ZFS tool fallback, ram_gib, encryption opts, pool
#                          creation helper, OS dataset creation, vdev spec
#                          builder
#   lib/layout/<mode>.sh — sourced after detect_mode(), before validation;
#                          implements the layout interface: layout_validate,
#                          layout_plan, layout_partition, layout_create_pools,
#                          layout_mount_esp
#   lib/packages.sh      — package collection, pacstrap
#   lib/zfs/verify.sh    — fail-fast ZFS Module Guard (post-pacstrap, ADR 0024)
#   lib/chroot.sh        — fstab, ESP mirror hook, arch-chroot configuration
#   lib/config/layers.sh       — host/user config loader+merger (host/user core)
#   lib/profiles.sh      — runs after configure_system: creates users,
#                          installs system + user programs from host/user
#                          configs
#   lib/config/validation.sh    — single seam for all config contract checks
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

# Parse recognised flags off the front of "$@", leaving any positional config
# path in $1 for the line that follows. Recognises -y/--unattended (sets the
# INSTALL_UNATTENDED env var consumed by lib/common.sh::confirm) and -h/--help.
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y | --unattended)
        export INSTALL_UNATTENDED=1
        shift
        ;;
      -h | --help)
        echo "Usage: $(basename "$0") [-y|--unattended] [CONFIG_FILE]"
        echo ""
        echo "  -y, --unattended  Bypass the final 'Proceed?' confirmation."
        echo "  -h, --help        Show this help and exit."
        exit 0
        ;;
      --)
        shift
        REMAINING_ARGS=("$@")
        return
        ;;
      -*)
        echo "[03-install.sh] Unknown option: $1" >&2
        exit 2
        ;;
      *)
        REMAINING_ARGS+=("$1")
        shift
        ;;
    esac
  done
}
REMAINING_ARGS=()
parse_args "$@"

# Path to the JSON config file. Can be overridden via command-line argument.
CONFIG_FILE="${REMAINING_ARGS[0]:-${SCRIPT_DIR}/install.jsonc}"

# Mountpoint for the new system during installation.
# shellcheck disable=SC2034 # consumed by sourced modules
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
source_module "${SCRIPT_DIR}/lib/zfs/module.sh"
source_module "${SCRIPT_DIR}/lib/kernel.sh"
source_module "${SCRIPT_DIR}/lib/config/categorized-list.sh"
source_module "${SCRIPT_DIR}/lib/config/accessors.sh"
source_module "${SCRIPT_DIR}/lib/install-state.sh"
source_module "${SCRIPT_DIR}/lib/config/lifecycle.sh"
source_module "${SCRIPT_DIR}/lib/secrets.sh"
source_module "${SCRIPT_DIR}/lib/config/layers.sh"
source_module "${SCRIPT_DIR}/lib/zfs/pools.sh"
source_module "${SCRIPT_DIR}/lib/zfs/pool-owners.sh"
source_module "${SCRIPT_DIR}/lib/packages.sh"
source_module "${SCRIPT_DIR}/lib/zfs/verify.sh"
source_module "${SCRIPT_DIR}/lib/chroot.sh"
source_module "${SCRIPT_DIR}/lib/profiles.sh"
source_module "${SCRIPT_DIR}/lib/config/validation.sh"
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
  [[ -d /sys/firmware/efi ]] \
    || error "Not in UEFI mode. Reboot and select a UEFI entry."

  # Install jq only if missing — skip the slow pacman -Sy if already present
  if ! command -v jq &>/dev/null; then
    info "Installing jq..."
    pacman -S --noconfirm --needed jq \
      || error "Failed to install jq. Run 01-bootstrap-zfs.sh first."
  fi

  # Quick connectivity check via TCP (faster than ping, works through more
  # firewalls). Uses /dev/tcp which is built into bash — zero external deps.
  if ! timeout 5 bash -c \
      'cat < /dev/null > /dev/tcp/archlinux.org/80' 2>/dev/null; then
    error "No internet connection. Required for pacstrap.
  Check: ip route show default   (needs a default gateway)
  Check: ping 8.8.8.8            (basic connectivity)"
  fi

  # ── Config phase ──────────────────────────────────────────────────────────
  load_config
  detect_mode
  export OS_DIR="${SCRIPT_DIR}"
  source_module "${SCRIPT_DIR}/lib/layout/${INSTALL_MODE}.sh"
  validate_install_context

  # ── Planning (topology resolution / size calculation) ─────────────────────
  layout_plan

  # ── Final confirmation (shows full plan, asks user to proceed) ────────────
  print_summary

  # ── Collect encryption passphrase before any disk writes ─────────────────
  # Must run after confirmation (user has committed) but before pool creation.
  # Collects once; piped to every zpool create call so all pools share one key.
  collect_enc_passphrase

  # ── Decrypt secrets before any disk writes ──────────────────────────────
  trap secrets_cleanup EXIT
  _age_key_url="$(cfgo '.options.age_key_url')"
  [[ -n "$_age_key_url" ]] && export SECRETS_KEY_URL="$_age_key_url"
  secrets_load "$RESOLVED_HOST_PROFILE"

  # ── Disk operations ───────────────────────────────────────────────────────
  layout_partition
  install_zfs_tools_if_needed
  layout_create_pools
  layout_mount_esp

  # ── Persist secrets state now that /mnt is mounted ────────────────────────
  secrets_persist_state

  # ── Install & configure ───────────────────────────────────────────────────
  install_base
  # Fail-fast before chroot config: every installed kernel must have a ZFS
  # module, else the install would crash later in mkinitcpio (ADR 0024).
  zfs_verify_target_modules
  configure_system

  # ── Profiles runner (host/user configs) ───────────────────────────────────
  run_profiles

  # ── Data-pool ownership (after users/groups exist, pools still mounted) ───
  # Makes /data pools writable by their owners + adds ~/Disks/<pool> symlinks
  # (ADR 0031). Runs before impermanence so the symlinks land in /home.
  pool_owners_apply

  # ── Impermanence (after users + programs, before unmount) ────────────────
  apply_impermanence

  # ── Print machine age key for sops updatekeys ─────────────────────────────
  secrets_print_machine_key

  # ── Cleanup ───────────────────────────────────────────────────────────────
  finalize
}

main "$@"
