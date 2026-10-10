#!/usr/bin/env bash
# =============================================================================
# lib/config/lifecycle.sh — Configuration management
# =============================================================================
# Used by: 03-install.sh, lib/feature-audit/manifest.sh.
# Requires: lib/common.sh already sourced.
#
# Provides:
#   lifecycle_load_config    — validates the config file exists and is valid
#                              JSON
#   lifecycle_detect_mode    — sets INSTALL_MODE from config or auto-detects
#   lifecycle_print_summary  — prints the installation plan and asks for
#                              confirmation
#
# Adding a new mode:
#   1. add an entry to _LIFECYCLE_MODE_SIGNATURES below (mode → defining JSON
#      path),
#   2. drop a lib/layout/<mode>.sh implementing the layout interface.
# =============================================================================

# shellcheck source=./environment.sh
source "${BASH_SOURCE[0]%/*}/environment.sh"

# shellcheck source=./post-install.sh
declare -F post_install_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/post-install.sh"

# =============================================================================
# RESOLVED GLOBALS — set during validate_install_context,
# consumed by configure_system
# =============================================================================
# shellcheck disable=SC2034 # consumed by validation.sh, profiles.sh, chroot.sh
RESOLVED_HOSTNAME=""
# shellcheck disable=SC2034 # consumed by validation.sh, profiles.sh, chroot.sh
RESOLVED_HOST_PROFILE=""

# =============================================================================
# MODE SIGNATURES — single source of truth for valid modes
# =============================================================================
# Each mode is defined by a "signature": a JSON path that must be present and
# non-empty. If multiple signatures match, lifecycle_detect_mode() errors — set
# 'mode' explicitly instead. validate_install_context() dispatches
# to _validation_<mode>().

declare -gA _LIFECYCLE_MODE_SIGNATURES=(
  [single]=".disk"
  [multi]=".os_pool.disks"
)

# =============================================================================
# CONFIG LOADING
# =============================================================================

lifecycle_load_config() {
  section "Loading Configuration"
  if [[ ! -f "$CONFIG_FILE" ]]; then
    error "Config not found: $CONFIG_FILE" \
      "Run bare ./install.sh for the Guided Installer, or pass a config" \
      "file (./install.sh <config>) or a profile (./install.sh --profile" \
      "<name>)."
  fi
  command_exists jq ||
    error "'jq' not found. Run 01-bootstrap-zfs.sh first."
  jsonc_strip "$CONFIG_FILE" | jq empty 2>/dev/null ||
    error "Invalid JSON: $CONFIG_FILE"
  info "Loaded: $CONFIG_FILE"
}

# =============================================================================
# MODE DETECTION
# =============================================================================

# Returns 0 if the given mode's JSON-path signature resolves to a non-null,
# non-empty value in the current config.
_lifecycle_mode_matches() {
  local mode="$1"
  local signature="${_LIFECYCLE_MODE_SIGNATURES[$mode]:-}"
  [[ -n "$signature" ]] || return 1

  if [[ "$signature" == *.disks ]]; then
    local disk_count
    disk_count="$(jsonc_strip "$CONFIG_FILE" | jq "${signature} | length // 0")"
    ((disk_count >= 1))
  else
    local value
    value="$(cfgo "$signature")"
    [[ -n "$value" ]]
  fi
}

lifecycle_detect_mode() {
  section "Detecting Install Mode"

  local configured_mode
  configured_mode="$(cfgo '.mode')"

  if [[ -n "$configured_mode" ]]; then
    [[ -v "_LIFECYCLE_MODE_SIGNATURES[$configured_mode]" ]] ||
      error "Unknown mode '${configured_mode}'." \
            "Valid: ${!_LIFECYCLE_MODE_SIGNATURES[*]}."
    INSTALL_MODE="$configured_mode"
    info "Mode from config: ${INSTALL_MODE}"
    return
  fi

  # Auto-detect: collect every mode whose signature is satisfied. Ambiguity
  # (two signatures match) is an explicit error — callers must set 'mode'.
  local mode matched=()
  while IFS= read -r mode; do
    _lifecycle_mode_matches "$mode" && matched+=("$mode")
  done < <(printf '%s\n' "${!_LIFECYCLE_MODE_SIGNATURES[@]}" | sort)

  if ((${#matched[@]} > 1)); then
    error "Ambiguous config: signatures for [${matched[*]}] all match." \
          "Set 'mode' explicitly."
  fi

  if ((${#matched[@]} == 1)); then
    INSTALL_MODE="${matched[0]}"
    info "Auto-detected mode: ${INSTALL_MODE}"
    return
  fi

  error "Cannot auto-detect mode." \
        "Set 'mode' to one of: ${!_LIFECYCLE_MODE_SIGNATURES[*]}."
}

# =============================================================================
# SUMMARY & CONFIRMATION
# =============================================================================

lifecycle_print_summary() {
  section "Installation Plan"

  if [[ "$INSTALL_MODE" == "single" ]]; then
    _lifecycle_print_single_disk_plan
  else
    _lifecycle_print_multi_disk_plan
  fi

  _lifecycle_print_packages

  echo ""
  echo -e "  ${BOLD}Environment:${NC}"
  print_environment_summary

  _lifecycle_print_extras
  _lifecycle_print_settings
  echo ""
  warn "ALL DATA ON THE LISTED DISKS WILL BE PERMANENTLY DESTROYED."
  confirm "Proceed with installation?"
}

# _lifecycle_disk_size <disk> — the disk's size as lsblk prints it, or "?".
_lifecycle_disk_size() {
  lsblk -dno SIZE "$1" 2>/dev/null || echo '?'
}

# _lifecycle_print_os_disks — one "<disk>  (<size>)" line per OS-pool disk.
_lifecycle_print_os_disks() {
  local disk
  while IFS= read -r disk; do
    printf "    %s  (%s)\n" "$disk" "$(_lifecycle_disk_size "$disk")"
  done < <(jsonc_strip "$CONFIG_FILE" | jq -r '.os_pool.disks[]')
}

_lifecycle_print_single_disk_plan() {
  local disk os_pool storage_pool storage_mount
  disk="$(cfgo '.disk')"
  os_pool="$(install_config_os_pool_name)"
  storage_pool="$(install_config_storage_pool_name)"
  storage_mount="$(install_config_storage_mount)"
  echo -e "\n  ${BOLD}Mode: single-disk${NC}"
  printf "    %-16s %s\n" "Disk:" "$disk  ($(_lifecycle_disk_size "$disk"))"
  printf "    %-16s %s\n" "OS pool:" "$os_pool  (no RAID, single partition)"
  printf "    %-16s %s\n" "Storage:" "$storage_pool → $storage_mount"
}

_lifecycle_print_multi_disk_plan() {
  local os_pool_name
  os_pool_name="$(cfg '.os_pool.pool_name')"
  echo -e "\n  ${BOLD}Mode: multi-disk${NC}"

  # The detailed multi summary reads the ZFS multi adapter's internal state
  # (topology / storage groups / standalone pools). A non-ZFS (btrfs) multi
  # root has none of that — print a simple topology + disk list instead.
  if [[ "$(install_config_filesystem)" != "zfs" ]]; then
    local topology
    topology="$(cfgo '.os_pool.topology')"
    [[ -z "$topology" ]] && topology=single
    echo -e "  ${BOLD}Root: $(install_config_filesystem) (${topology})${NC}"
    _lifecycle_print_os_disks
    return 0
  fi

  _lifecycle_print_zfs_os_pool "$os_pool_name"
  _lifecycle_print_zfs_data_pool
  _lifecycle_print_standalone_data_pools
}

_lifecycle_print_zfs_os_pool() {
  local os_pool_name="$1" os_topology os_disk
  os_topology="$(layout_os_topology)"
  os_disk="$(layout_os_disk)"
  echo -e "  ${BOLD}OS pool: ${os_pool_name}${NC}" \
          " topology: ${os_topology}"

  if [[ "$os_topology" != "none" ]]; then
    _lifecycle_print_os_disks
    return 0
  fi
  printf "    OS disk  : %s  (%s)\n" "$os_disk" \
    "$(_lifecycle_disk_size "$os_disk")"
  local leftover_disks joined
  mapfile -t leftover_disks < <(layout_leftover_disks)
  joined="${leftover_disks[*]}"
  [[ -n "$joined" ]] &&
    printf "    → dpool  : %s\n" "$joined"
  return 0
}

_lifecycle_print_zfs_data_pool() {
  local storage_group_count has_leftover=false
  storage_group_count="$(jsonc_strip "$CONFIG_FILE" \
    | jq '.storage_groups | length')"
  layout_has_leftover && has_leftover=true
  ((storage_group_count > 0)) || $has_leftover || return 0

  echo -e "\n  ${BOLD}Data pool: dpool${NC}"
  local i group_name group_mount group_topology
  for ((i = 0; i < storage_group_count; i++)); do
    group_name="$(cfg ".storage_groups[$i].name")"
    group_mount="$(cfg ".storage_groups[$i].mount")"
    group_topology="$(layout_group_topology "$group_name")"
    printf "    '%-12s  → %-20s  topology: %s\n" \
      "${group_name}'" "$group_mount" "${group_topology:-?}"
  done
  if $has_leftover; then
    local leftover_topology
    leftover_topology="$(layout_group_topology _leftover)"
    printf "    '%-12s  → %-20s  topology: %s\n" \
      "extra (auto)'" "/data/extra" "${leftover_topology:-independent}"
  fi
}

_lifecycle_print_standalone_data_pools() {
  local data_pool_names data_pool
  data_pool_names="$(layout_data_pool_names)"
  [[ -n "$data_pool_names" ]] || return 0
  echo -e "\n  ${BOLD}Standalone data pools:${NC}"
  while IFS= read -r data_pool; do
    printf "    '%-12s  → %-20s  topology: %s\n" \
      "${data_pool}'" "$(layout_data_pool_mount "$data_pool")" \
      "$(layout_data_pool_topo "$data_pool")"
  done <<<"$data_pool_names"
}

# Packages — one line per packages.repo category (the sole authored repo
# slot now that extra/groups are gone).
_lifecycle_print_packages() {
  echo ""
  echo -e "  ${BOLD}Packages:${NC}"
  local category names
  while IFS=$'\t' read -r category names; do
    [[ -n "$names" ]] && printf "    %s: %s\n" "$category" "$names"
  done < <(jsonc_strip "$CONFIG_FILE" | jq -r '
    (.packages.repo // {}) | to_entries[]
    | select(.value | type == "array")
    | "\(.key)\t\(.value | join(", "))"')
}

# Security & Backup Extras (ADR 0041) — the resolved program list installed
# via the Primary User's paru pass. Empty when nothing is selected.
_lifecycle_print_extras() {
  local post_install_json extras
  post_install_json="$(jsonc_strip "$CONFIG_FILE" \
    | jq -c '.post_install // {}')"
  # Joined the way `paste -sd ', '` always did: the separators alternate
  # "," then " " (bug filed separately — the intent was ", ").
  extras="$(post_install_programs "$post_install_json" \
      "$(install_config_any_zfs)" \
    | awk '{ printf "%s%s", (NR == 1 ? "" : (NR % 2 == 0 ? "," : " ")), $0 }
           END { if (NR) print "" }')"
  echo ""
  echo -e "  ${BOLD}Security & Backup Extras:${NC}"
  printf "    %-12s %s\n" "install:" "${extras:-(none)}"
}

_lifecycle_print_settings() {
  echo ""
  local encryption swap_enabled zswap_note hostname dotfiles_repo
  encryption="$(install_config_encryption_enabled)"
  swap_enabled="$(install_config_swap_enabled)"
  zswap_note=""
  if [[ "$swap_enabled" == "true" \
        && "$(install_config_zswap_enabled)" == "true" ]]; then
    zswap_note="  ·  zswap ($(install_config_zswap_compressor))"
  fi
  hostname="$(install_config_hostname)"
  hostname="${hostname:-(prompted during install)}"
  printf "  %-16s %s\n" "Hostname:" "$hostname"
  # Resolved, not raw (ADR 0118): shows the value that will actually apply
  # (explicit/guided → geo-IP autodetect → Europe/Bucharest), and never aborts
  # on an absent field the way the required-field cfg reader would.
  printf "  %-16s %s\n" "Timezone:" "$(install_config_timezone)"
  printf "  %-16s %s\n" "Encryption:" "$encryption"
  printf "  %-16s %s\n" "Swap:" "$swap_enabled  (auto = RAM × 2)$zswap_note"
  dotfiles_repo="$(install_config_dotfiles_repo)"
  [[ -n "$dotfiles_repo" ]] && \
    printf "  %-16s %s\n" "Dotfiles:" "$dotfiles_repo"
  return 0
}
