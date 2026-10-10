#!/usr/bin/env bash
# =============================================================================
# 03-install.sh — Arch Linux ZFS Installer (orchestrator)
# =============================================================================
# Intentionally thin: main() below is the whole install as a table of
# contents; each phase is a short function under it, and all logic lives in
# lib/ (the source_module block at the bottom).
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
# MAIN — the install, phase by phase
# =============================================================================

main() {
  print_banner
  check_prerequisites
  load_configuration
  plan_and_confirm
  prepare_secrets
  prepare_disks
  install_system
  configure_users_and_programs
  finish_install
}

# =============================================================================
# PHASES
# =============================================================================

print_banner() {
  echo -e "\n${CYAN}${BOLD}  Arch Linux ZFS Installer${NC}"
  echo -e "${DIM}  ─────────────────────────────────────────────────${NC}"
  echo -e "${DIM}  Config : ${CONFIG_FILE}${NC}"
  echo -e "${DIM}  Modules: ${SCRIPT_DIR}/lib/${NC}\n"
}

check_prerequisites() {
  [[ $EUID -eq 0 ]] || error "Run as root (sudo -i)."
  [[ -d /sys/firmware/efi ]] \
    || error "Not in UEFI mode. Reboot and select a UEFI entry."

  # Install jq only if missing — skip the slow pacman -Sy if already present
  if ! command_exists jq; then
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
}

load_configuration() {
  lifecycle_load_config
  lifecycle_detect_mode
  export INSTALLER_DIR="${SCRIPT_DIR}"
  # Layout dispatch (ADR 0040/0043/0073): the disk-config kind wins first — a
  # manual layout owns the disk regardless of filesystem — otherwise the Root
  # Layout Adapter is chosen by the filesystem discriminator + mode.
  local layout_adapter
  layout_adapter="$(root_adapter_for_kind "${SCRIPT_DIR}" \
    "$(install_config_disk_kind)" "$(install_config_filesystem)" \
    "${INSTALL_MODE}")" \
    || error "Cannot select a layout adapter for the configured filesystem."
  source_module "${layout_adapter}"
  validate_install_context
}

# Topology resolution / size calculation, then the full plan and the
# "Proceed?" confirmation.
plan_and_confirm() {
  layout_plan
  lifecycle_print_summary
}

# Runs after confirmation but before any disk write.
prepare_secrets() {
  # Collects the encryption passphrase once; piped to every zpool create so
  # all pools share one key.
  collect_enc_passphrase

  trap secrets_cleanup EXIT
  local age_key_url
  age_key_url="$(config_optional '.options.age_key_url')"
  [[ -n "$age_key_url" ]] && export SECRETS_KEY_URL="$age_key_url"
  secrets_load "$RESOLVED_HOST_PROFILE"
}

prepare_disks() {
  layout_partition
  # ZFS userland is only needed when some group is ZFS; a pure non-ZFS install
  # skips it (ADR 0043).
  [[ "$(install_config_any_zfs)" == "true" ]] && install_zfs_tools_if_needed
  layout_create_pools
  layout_mount_esp

  # Persist secrets state now that /mnt is mounted.
  secrets_persist_state

  # Guided no-SOPS passwords: persist the staged manifest into install-state
  # under .guided_passwords.* (unlike .secrets.*, doesn't activate the SOPS
  # runtime program). The chroot + Runner credential resolvers read it.
  guided_persist_passwords "${INSTALL_STATE:-/mnt/install-state.json}"
}

install_system() {
  install_base
  # Fail-fast before chroot config: every SELECTED kernel must have a ZFS
  # module, else mkinitcpio crashes later (ADR 0024). A stray kernel pulled in
  # as a dependency (not in options.kernel) is tolerated — warned, non-fatal
  # (ADR 0138). Only when some group is ZFS (ADR 0043).
  if [[ "$(install_config_any_zfs)" == "true" ]]; then
    local selected_kernel_packages=() kernel
    while IFS= read -r kernel; do
      [[ -n "$kernel" ]] || continue
      selected_kernel_packages+=("$(kernel_pkg "$kernel")")
    done < <(install_config_kernels)
    zfs_verify_target_modules "${MOUNT_ROOT:-/mnt}" \
      "${selected_kernel_packages[@]}"
  fi
  configure_system
}

configure_users_and_programs() {
  run_profiles
  # the Audit Cache (test-only) served the install; ship pacman.conf as is
  strip_audit_cache "${MOUNT_ROOT:-/mnt}/etc/pacman.conf"

  # Wipe the staged plaintext guided passwords now the Runner has consumed them.
  guided_secrets_cleanup

  # Data-pool ownership (after users/groups exist, pools still mounted): make
  # /data pools writable by their owners + add ~/Disks/<pool> symlinks
  # (ADR 0031). Before impermanence so the symlinks land in /home.
  pool_owners_apply

  # Impermanence: after users + programs, before unmount.
  apply_impermanence
}

finish_install() {
  # Print the machine age key for sops updatekeys.
  secrets_print_machine_key
  finalize
}

# =============================================================================
# STARTUP — arguments, global constants, modules
# =============================================================================

# Dir of this script; all lib/ paths and the default config are relative to it.
# (The stdlib is not loaded yet, so no parent_directory here; a bare
# `bash 03-install.sh` has no slash to strip, hence the ./ prefix.)
script_path="${BASH_SOURCE[0]}"
[[ "$script_path" == */* ]] || script_path="./$script_path"
SCRIPT_DIR="$(cd "${script_path%/*}" && pwd)"

# Parse recognised flags off "$@", leaving a positional config path behind.
# -y/--unattended sets INSTALL_UNATTENDED (consumed by lib/common.sh::confirm).
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y | --unattended)
        export INSTALL_UNATTENDED=1
        shift
        ;;
      -h | --help)
        echo "Usage: ${0##*/} [-y|--unattended] [CONFIG_FILE]"
        echo ""
        echo "  -y, --unattended  Bypass the final 'Proceed?' confirmation."
        echo "  -h, --help        Show this help and exit."
        exit 0
        ;;
      --)
        shift
        REMAINING_ARGUMENTS=("$@")
        return
        ;;
      -*)
        echo "[03-install.sh] Unknown option: $1" >&2
        exit 2
        ;;
      *)
        REMAINING_ARGUMENTS+=("$1")
        shift
        ;;
    esac
  done
}
REMAINING_ARGUMENTS=()
parse_arguments "$@"

# Config path; overridable via positional argument.
CONFIG_FILE="${REMAINING_ARGUMENTS[0]:-${SCRIPT_DIR}/install.jsonc}"

# Mountpoint for the new system during installation.
# shellcheck disable=SC2034 # consumed by sourced modules
MOUNT_ROOT="/mnt"

source_module() {
  local path="$1"
  [[ -f "$path" ]] || {
    echo -e "\033[0;31m[ERROR]\033[0m Required module not found: $path" >&2
    exit 1
  }
  # shellcheck source=/dev/null
  source "$path"
}

# Sourced at top level, not inside a function: a module's plain `declare -A`
# would otherwise become function-local.
source_module "${SCRIPT_DIR}/lib/common.sh"
source_module "${SCRIPT_DIR}/lib/prompt.sh"
source_module "${SCRIPT_DIR}/lib/zfs/module.sh"
source_module "${SCRIPT_DIR}/lib/packages/kernel.sh"
source_module "${SCRIPT_DIR}/lib/packages/microcode.sh"
source_module "${SCRIPT_DIR}/lib/config/categorized-list.sh"
source_module "${SCRIPT_DIR}/lib/config/post-install.sh"
source_module "${SCRIPT_DIR}/lib/config/accessors.sh"
source_module "${SCRIPT_DIR}/lib/config/timezone.sh"
source_module "${SCRIPT_DIR}/lib/install-state.sh"
source_module "${SCRIPT_DIR}/lib/config/lifecycle.sh"
source_module "${SCRIPT_DIR}/lib/secrets.sh"
source_module "${SCRIPT_DIR}/lib/guided/secrets.sh"
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

main "$@"
