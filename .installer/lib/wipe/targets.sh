#!/usr/bin/env bash
# =============================================================================
# lib/wipe/targets.sh — the Target Resolver
# =============================================================================
# Resolves an install's target disks from the Install Config so the Single
# Entry Point can pass them to the wipe as an explicit list. The wipe then
# touches only disks the install will use and stays config-agnostic itself.
#
# Pure decision over the config file (no block-device access). Sourced by
# install.sh; main()-free, so sourcing is inert.
# =============================================================================

# shellcheck source=../jsonc.sh
declare -F jsonc_strip >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../jsonc.sh"
# shellcheck source=../config/install-config.sh
declare -F install_config_disk_kind >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/install-config.sh"

# wipe_resolve_targets CONFIG_FILE → target device paths, one per line,
# deduplicated (a disk reused across sections is emitted once). `unique` also
# sorts; order is immaterial to a wipe set. A manual disk_config resolves to
# nothing: the operator's hand-drawn table must survive (ADR 0073).
wipe_resolve_targets() {
  [[ "$(CONFIG_FILE="$1" install_config_disk_kind)" == manual ]] && return 0
  local config
  config="$(jsonc_strip "$1")"
  # Every disk the config names (the single disk, the OS pool's, each
  # storage group's and data pool's), then each once, in C order.
  {
    printf '%s\n' "$config" | jq -r '.disk // empty'
    printf '%s\n' "$config" | jq -r '.os_pool.disks // [] | .[]'
    printf '%s\n' "$config" | jq -r '.storage_groups[]?.disks // [] | .[]'
    printf '%s\n' "$config" | jq -r '.data_pools[]?.disks // [] | .[]'
  } | LC_ALL=C sort -u
}
