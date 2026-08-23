#!/usr/bin/env bash
# =============================================================================
# 03-install.sh — Arch Linux ZFS Installer (orchestrator)
# =============================================================================
# Intentionally thin: sets global constants, sources the lib/ modules (see the
# source_module block below), and defines main(). All logic lives in lib/.
# Run order: 01-bootstrap → 02-wipe (optional) → 03-install. A missing
# install.jsonc generates a documented template, then exits for you to edit.
# Honors INSTALL_UNATTENDED=1 from env or the -y flag. See -h for usage.
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

# Dir of this script; all lib/ paths and the default config are relative to it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse recognised flags off "$@", leaving a positional config path behind.
# -y/--unattended sets INSTALL_UNATTENDED (consumed by lib/common.sh::confirm).
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

# Config path; overridable via positional argument.
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
source_module "${SCRIPT_DIR}/lib/prompt.sh"
source_module "${SCRIPT_DIR}/lib/zfs/module.sh"
source_module "${SCRIPT_DIR}/lib/packages/kernel.sh"
source_module "${SCRIPT_DIR}/lib/packages/microcode.sh"
source_module "${SCRIPT_DIR}/lib/config/categorized-list.sh"
source_module "${SCRIPT_DIR}/lib/config/post-install.sh"
source_module "${SCRIPT_DIR}/lib/config/accessors.sh"
source_module "${SCRIPT_DIR}/lib/install-state.sh"
source_module "${SCRIPT_DIR}/lib/config/lifecycle.sh"
source_module "${SCRIPT_DIR}/lib/secrets.sh"
source_module "${SCRIPT_DIR}/lib/guided-secrets.sh"
source_module "${SCRIPT_DIR}/lib/config/layers.sh"
source_module "${SCRIPT_DIR}/lib/config/profile.sh"
source_module "${SCRIPT_DIR}/lib/layout/dispatch.sh"
source_module "${SCRIPT_DIR}/lib/zfs/pools.sh"
source_module "${SCRIPT_DIR}/lib/zfs/pool-owners.sh"
source_module "${SCRIPT_DIR}/lib/packages/list.sh"
source_module "${SCRIPT_DIR}/lib/zfs/verify.sh"
source_module "${SCRIPT_DIR}/lib/chroot.sh"
source_module "${SCRIPT_DIR}/lib/profiles/runner.sh"
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

  # Quick TCP check via bash's /dev/tcp — faster than ping, no deps.
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
  # Layout dispatch (ADR 0040/0043/0073): the disk-config kind wins first — a
  # manual layout owns the disk regardless of filesystem — otherwise the Root
  # Layout Adapter is chosen by the filesystem discriminator + mode.
  local _layout_adapter
  _layout_adapter="$(root_adapter_for_kind "${SCRIPT_DIR}" \
    "$(install_config_disk_kind)" "$(install_config_filesystem)" \
    "${INSTALL_MODE}")" \
    || error "Cannot select a layout adapter for the configured filesystem."
  source_module "${_layout_adapter}"
  validate_install_context

  # ── Planning (topology resolution / size calculation) ─────────────────────
  layout_plan

  # ── Final confirmation (shows full plan, asks user to proceed) ────────────
  print_summary

  # ── Collect encryption passphrase before any disk writes ─────────────────
  # Must run after confirmation but before pool creation. Collects once; piped
  # to every zpool create so all pools share one key.
  collect_enc_passphrase

  # ── Decrypt secrets before any disk writes ──────────────────────────────
  trap secrets_cleanup EXIT
  _age_key_url="$(cfgo '.options.age_key_url')"
  [[ -n "$_age_key_url" ]] && export SECRETS_KEY_URL="$_age_key_url"
  secrets_load "$RESOLVED_HOST_PROFILE"

  # ── Disk operations ───────────────────────────────────────────────────────
  layout_partition
  # ZFS userland is only needed when some group is ZFS; a pure non-ZFS install
  # skips it (ADR 0043).
  [[ "$(install_config_any_zfs)" == "true" ]] && install_zfs_tools_if_needed
  layout_create_pools
  layout_mount_esp

  # ── Persist secrets state now that /mnt is mounted ────────────────────────
  secrets_persist_state

  # Guided no-SOPS passwords: persist the staged manifest into install-state
  # under .guided_passwords.* (unlike .secrets.*, doesn't activate the SOPS
  # runtime program). The chroot + Runner credential resolvers read it.
  guided_persist_passwords "${INSTALL_STATE:-/mnt/install-state.json}"

  # ── Install & configure ───────────────────────────────────────────────────
  install_base
  # Fail-fast before chroot config: every kernel must have a ZFS module, else
  # mkinitcpio crashes later (ADR 0024). Only when some group is ZFS (ADR 0043).
  [[ "$(install_config_any_zfs)" == "true" ]] && zfs_verify_target_modules
  configure_system

  # ── Profiles runner (host/user configs) ───────────────────────────────────
  run_profiles

  # Wipe the staged plaintext guided passwords now the Runner has consumed them.
  guided_secrets_cleanup

  # ── Data-pool ownership (after users/groups exist, pools still mounted) ───
  # Make /data pools writable by their owners + add ~/Disks/<pool> symlinks
  # (ADR 0031). Before impermanence so the symlinks land in /home.
  pool_owners_apply

  # ── Impermanence (after users + programs, before unmount) ────────────────
  apply_impermanence

  # ── Print machine age key for sops updatekeys ─────────────────────────────
  secrets_print_machine_key

  # ── Cleanup ───────────────────────────────────────────────────────────────
  finalize
}

main "$@"
