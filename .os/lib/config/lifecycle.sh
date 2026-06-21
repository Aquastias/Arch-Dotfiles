#!/usr/bin/env bash
# =============================================================================
# lib/config/lifecycle.sh — Configuration management
# =============================================================================
# Sourced by 03-install.sh.
# Requires: lib/common.sh already sourced.
#
# Provides:
#   load_config        — validates the config file exists and is valid JSON
#   detect_mode        — sets INSTALL_MODE from config or auto-detects
#   print_summary      — prints the installation plan and asks for confirmation
#
# Adding a new mode:
#   1. add an entry to _CONFIG_MODE_SIG below (mode → defining JSON path),
#   2. drop a lib/layout/<mode>.sh implementing the layout interface.
# =============================================================================

# shellcheck source=./environment.sh
source "${BASH_SOURCE[0]%/*}/environment.sh"

# shellcheck source=./post-install.sh
[[ "$(type -t post_install_programs)" == "function" ]] \
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
# non-empty. If multiple signatures match, detect_mode() errors — set 'mode'
# explicitly instead. validate_install_context() dispatches
# to _validation_<mode>().

declare -gA _CONFIG_MODE_SIG=(
  [single]=".disk"
  [multi]=".os_pool.disks"
)

# =============================================================================
# CONFIG LOADING
# =============================================================================

load_config() {
  section "Loading Configuration"
  if [[ ! -f "$CONFIG_FILE" ]]; then
    error "Config not found: $CONFIG_FILE" \
      "Run bare ./install.sh for the Guided Installer, or pass a config" \
      "file (./install.sh <config>) or a profile (./install.sh --profile" \
      "<name>)."
  fi
  command -v jq &>/dev/null ||
    error "'jq' not found. Run 01-bootstrap-zfs.sh first."
  jsonc_strip "$CONFIG_FILE" | jq empty 2>/dev/null ||
    error "Invalid JSON: $CONFIG_FILE"
  info "Loaded: $CONFIG_FILE"
}

# =============================================================================
# MODE DETECTION
# =============================================================================
# Picks the mode by signature presence in the config. Returns 0 if the given
# mode's JSON-path signature resolves to a non-null, non-empty value.

# Returns 0 if the given mode's signature is satisfied by the current config.
_config_mode_matches() {
  local mode="$1"
  local sig="${_CONFIG_MODE_SIG[$mode]:-}"
  [[ -n "$sig" ]] || return 1

  if [[ "$sig" == *.disks ]]; then
    local cnt
    cnt="$(jsonc_strip "$CONFIG_FILE" | jq "${sig} | length // 0")"
    ((cnt >= 1))
  else
    local v
    v="$(cfgo "$sig")"
    [[ -n "$v" ]]
  fi
}

detect_mode() {
  section "Detecting Install Mode"

  local cfg_mode
  cfg_mode="$(cfgo '.mode')"

  if [[ -n "$cfg_mode" ]]; then
    [[ -v "_CONFIG_MODE_SIG[$cfg_mode]" ]] ||
      error "Unknown mode '${cfg_mode}'. Valid: ${!_CONFIG_MODE_SIG[*]}."
    INSTALL_MODE="$cfg_mode"
    info "Mode from config: ${INSTALL_MODE}"
    return
  fi

  # Auto-detect: collect every mode whose signature is satisfied. Ambiguity
  # (two signatures match) is an explicit error — callers must set 'mode'.
  local m matched=()
  for m in $(echo "${!_CONFIG_MODE_SIG[@]}" | tr ' ' '\n' | sort); do
    _config_mode_matches "$m" && matched+=("$m")
  done

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
        "Set 'mode' to one of: ${!_CONFIG_MODE_SIG[*]}."
}


# =============================================================================
# SUMMARY & CONFIRMATION
# =============================================================================


print_summary() {
  section "Installation Plan"

  if [[ "$INSTALL_MODE" == "single" ]]; then
    local d
    d="$(cfgo '.disk')"
    local sz
    sz="$(lsblk -dno SIZE "$d" 2>/dev/null || echo '?')"
    local rp dp mnt
    rp="$(install_config_os_pool_name)"
    dp="$(install_config_storage_pool_name)"
    mnt="$(install_config_storage_mount)"
    echo -e "\n  ${BOLD}Mode: single-disk${NC}"
    printf "    %-16s %s\n" "Disk:" "$d  ($sz)"
    printf "    %-16s %s\n" "OS pool:" "$rp  (no RAID, single partition)"
    printf "    %-16s %s\n" "Storage:" "$dp → $mnt"

  else # multi
    local op
    op="$(cfg '.os_pool.pool_name')"
    echo -e "\n  ${BOLD}Mode: multi-disk${NC}"
    echo -e "  ${BOLD}OS pool: ${op}${NC}" \
            " topology: ${_LAYOUT_IMPL_OS_TOPOLOGY}"

    if [[ "$_LAYOUT_IMPL_OS_TOPOLOGY" == "none" ]]; then
      local s
      s="$(lsblk -dno SIZE "$_LAYOUT_IMPL_OS_DISK" 2>/dev/null || echo '?')"
      printf "    OS disk  : %s  (%s)\n" "$_LAYOUT_IMPL_OS_DISK" "$s"
      ((${#_LAYOUT_IMPL_LEFTOVER_DISKS[@]} > 0)) &&
        printf "    → dpool  : %s\n" "${_LAYOUT_IMPL_LEFTOVER_DISKS[*]}"
    else
      while IFS= read -r d; do
        local s
        s="$(lsblk -dno SIZE "$d" 2>/dev/null || echo '?')"
        printf "    %s  (%s)\n" "$d" "$s"
      done < <(jsonc_strip "$CONFIG_FILE" | jq -r '.os_pool.disks[]')
    fi

    local sg
    sg="$(jsonc_strip "$CONFIG_FILE" | jq '.storage_groups | length')"
    local has_left=false
    [[ -v "_LAYOUT_IMPL_STORAGE_PARTS[_leftover]" ]] && has_left=true

    if ((sg > 0)) || $has_left; then
      echo -e "\n  ${BOLD}Data pool: dpool${NC}"
      for ((i = 0; i < sg; i++)); do
        local gn
        gn="$(cfg ".storage_groups[$i].name")"
        local gm
        gm="$(cfg ".storage_groups[$i].mount")"
        local gt="${_LAYOUT_IMPL_TOPOLOGIES[$gn]:-?}"
        printf "    '%-12s  → %-20s  topology: %s\n" "${gn}'" "$gm" "$gt"
      done
      if $has_left; then
        printf "    '%-12s  → %-20s  topology: %s\n" \
          "extra (auto)'" "/data/extra" \
          "${_LAYOUT_IMPL_TOPOLOGIES[_leftover]:-independent}"
      fi
    fi

    if ((${#_LAYOUT_IMPL_DATA_POOL_NAMES[@]} > 0)); then
      echo -e "\n  ${BOLD}Standalone data pools:${NC}"
      local dpn
      for dpn in "${_LAYOUT_IMPL_DATA_POOL_NAMES[@]}"; do
        printf "    '%-12s  → %-20s  topology: %s\n" \
          "${dpn}'" "${_LAYOUT_IMPL_DATA_POOL_MOUNT[$dpn]}" \
          "${_LAYOUT_IMPL_DATA_POOL_TOPO[$dpn]}"
      done
    fi
  fi

  # Packages
  local extras
  extras="$(jsonc_strip "$CONFIG_FILE" \
    | jq -r '(.packages.extra // []) | join(", ")')"
  local cli
  cli="$(jsonc_strip "$CONFIG_FILE" \
    | jq -r '(.packages.groups.cli // []) | join(", ")')"
  local dev
  dev="$(jsonc_strip "$CONFIG_FILE" \
    | jq -r '(.packages.groups.dev // []) | join(", ")')"
  local gui
  gui="$(jsonc_strip "$CONFIG_FILE" \
    | jq -r '(.packages.groups.gui // []) | join(", ")')"
  echo ""
  echo -e "  ${BOLD}Packages:${NC}"
  [[ -n "$extras" ]] && printf "    extra: %s\n" "$extras"
  [[ -n "$cli" ]] && printf "    cli:   %s\n" "$cli"
  [[ -n "$dev" ]] && printf "    dev:   %s\n" "$dev"
  [[ -n "$gui" ]] && printf "    gui:   %s\n" "$gui"

  # Environment
  echo ""
  echo -e "  ${BOLD}Environment:${NC}"
  print_environment_summary

  # Security & Backup Extras (ADR 0041) — the resolved program list installed
  # via the Primary User's paru pass. Empty when nothing is selected.
  local _pi _extras
  _pi="$(jsonc_strip "$CONFIG_FILE" | jq -c '.post_install // {}')"
  _extras="$(post_install_programs "$_pi" | paste -sd ', ')"
  echo ""
  echo -e "  ${BOLD}Security & Backup Extras:${NC}"
  printf "    %-12s %s\n" "install:" "${_extras:-(none)}"

  echo ""
  local enc; enc="$(install_config_encryption_enabled)"
  local swap
  swap="$(install_config_swap_enabled)"
  local _hn
  _hn="$(install_config_hostname)"
  _hn="${_hn:-(prompted during install)}"
  printf "  %-16s %s\n" "Hostname:" "$_hn"
  printf "  %-16s %s\n" "Timezone:" "$(cfg '.system.timezone')"
  printf "  %-16s %s\n" "Encryption:" "$enc"
  printf "  %-16s %s\n" "Swap:" "$swap  (auto = RAM × 2)"
  local _dr
  _dr="$(install_config_dotfiles_repo)"
  [[ -n "$_dr" ]] && printf "  %-16s %s\n" "Dotfiles:" "$_dr"
  echo ""
  warn "ALL DATA ON THE LISTED DISKS WILL BE PERMANENTLY DESTROYED."
  confirm "Proceed with installation?"
}
