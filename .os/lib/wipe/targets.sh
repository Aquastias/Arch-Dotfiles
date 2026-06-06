#!/usr/bin/env bash
# =============================================================================
# lib/wipe/targets.sh — the Target Resolver
# =============================================================================
# Resolves an install's target disks from the Install Config so the Single Entry
# Point can pass them to the wipe as an explicit list. The wipe then touches only
# disks the install will use and stays config-agnostic itself.
#
# Pure decision over the config file (no block-device access). Sourced by
# install.sh; main()-free, so sourcing is inert.
# =============================================================================

# shellcheck source=../jsonc.sh
[[ "$(type -t jsonc_strip)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/../jsonc.sh"

# wipe_resolve_targets CONFIG_FILE → target device paths, one per line,
# deduplicated (a disk reused across sections is emitted once). `unique` also
# sorts; order is immaterial to a wipe set.
wipe_resolve_targets() {
  jsonc_strip "$1" | jq -r '
    [ (.disk // empty),
      (.os_pool.disks // [])[],
      (.storage_groups[]?.disks // [])[],
      (.data_pools[]?.disks // [])[] ] | unique | .[]'
}
