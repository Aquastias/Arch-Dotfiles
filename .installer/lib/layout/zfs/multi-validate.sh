#!/usr/bin/env bash
# =============================================================================
# lib/layout/zfs/multi-validate.sh — multi-disk config validation
# =============================================================================
# Used by: lib/layout/zfs/multi.sh (sources it). layout_validate for the ZFS
# multi-disk Root Layout Adapter: OS pool, storage groups, Standalone Data
# Pools, and the cross-pool name/disk/mount rules. Pure checks — no disk is
# touched; the first problem aborts via `error`.
# =============================================================================

# =============================================================================
# VALIDATION HELPERS (issue 03/04)
# =============================================================================

# layout_disk_exists is the shared disk-existence seam from lib/layout/core.sh
# (sourced via zfs/common.sh); multi's existence checks call it directly.

# _picker_group_min: the per-topology disk minimums the menu enforces.
# shellcheck source=../../picker.sh
declare -F _picker_group_min >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../../picker.sh"

_zfs_multi_validate_declared_users() {
  # Seam: declared usernames (space-separated, Primary User first) used to
  # validate `owners` lists. Reads the resolved host config; overridable in
  # unit tests so the owners checks don't need a real host config on disk.
  _pool_owners_declared_users
}

_zfs_multi_validate_owners() {
  # Aborts the install when <owners> is invalid (pool-owners, ADR 0031): a
  # bare name must be a declared user; an @group must have ≥1 declared member.
  # No-op when owners is omitted — that case defaults to the Primary User, or
  # is left root-owned with a warning on a host with no declared users.
  local label="$1" owners="$2"
  [[ -n "${owners// }" ]] || return 0
  local reason
  reason="$(zfs_pool_owners_validate "$owners" \
    "$(_zfs_multi_validate_declared_users)" \
    "$(_zfs_multi_validate_group_map)")" \
    || error "${label} ${reason}"
}

_zfs_multi_validate_group_map() {
  # Seam: "group:member1,member2" pairs for @group owners validation. Built
  # from User Configs; overridable in unit tests.
  _pool_owners_group_map
}

_zfs_multi_validate_mount_is_reserved() {
  # Returns 0 when the mountpoint shadows an OS/reserved dataset, so a data
  # pool can't break boot. Subtree semantics (not bare prefix): /var and
  # /boot match their whole subtree; /data, /variable etc. are free.
  case "$1" in
  / | /home | /tmp | /persist) return 0 ;;
  /var | /var/* | /boot | /boot/*) return 0 ;;
  esac
  return 1
}

# =============================================================================
# LAYOUT INTERFACE (called by 03-install.sh)
# =============================================================================

layout_validate() {
  layout_enter_phase validate
  layout_validate_esp_size
  _zfs_multi_validate_os_pool
  _zfs_multi_validate_storage_groups

  local data_pool_count
  data_pool_count="$(jsonc_strip "$CONFIG_FILE" \
    | jq '(.data_pools // []) | length')"
  _zfs_multi_validate_data_pools "$data_pool_count"
  _zfs_multi_validate_unique_disks
  # Cross-cutting data-pool guards (only when data_pools are declared, so
  # existing multi configs without them are untouched).
  if ((data_pool_count > 0)); then
    _zfs_multi_validate_unique_names
    _zfs_multi_validate_mounts
    _zfs_multi_validate_data_disks_exist "$data_pool_count"
  fi
  layout_exit_phase validate
}

_zfs_multi_validate_os_pool() {
  local topology disk_count disk message
  topology="$(config_optional '.os_pool.topology')"
  if [[ -n "$topology" ]]; then
    case "$topology" in
    mirror | stripe | none | raidz1 | raidz2) ;;
    *) error "os_pool.topology must be mirror|stripe|none|raidz1|raidz2," \
             "got: '${topology}'" ;;
    esac
  fi

  disk_count="$(jsonc_strip "$CONFIG_FILE" | jq '.os_pool.disks | length')"
  ((disk_count >= 1)) || error "os_pool.disks must list at least 1 disk."
  # raidz needs its parity disks (the menu's minimums)
  if [[ "$topology" == raidz* ]] \
     && ! message="$(_picker_group_min "$topology" "$disk_count" 2>&1)"; then
    error "os_pool: ${message}"
  fi

  while IFS= read -r disk; do
    layout_disk_exists "$disk" || error "OS disk not found: $disk"
  done < <(jsonc_strip "$CONFIG_FILE" | jq -r '.os_pool.disks[]')
}

_zfs_multi_validate_storage_groups() {
  local storage_group_count group_name group_disk_count i disk
  storage_group_count="$(jsonc_strip "$CONFIG_FILE" \
    | jq '.storage_groups | length')"
  for ((i = 0; i < storage_group_count; i++)); do
    group_name="$(config_required ".storage_groups[$i].name")"
    group_disk_count="$(jsonc_strip "$CONFIG_FILE" \
      | jq ".storage_groups[$i].disks | length")"
    ((group_disk_count >= 1)) \
      || error "Storage group '${group_name}' has no disks."
    while IFS= read -r disk; do
      layout_disk_exists "$disk" \
        || error "Group '${group_name}' disk not found: $disk"
    done < <(jsonc_strip "$CONFIG_FILE" | jq -r ".storage_groups[$i].disks[]")
    _zfs_multi_validate_owners "Storage group '${group_name}'" \
      "$(install_config_storage_group_owners "$i" \
         | awk '{ printf "%s ", $0 }')"
  done
}

# Standalone Data Pools (ADR 0027): topology must match the disk count and
# cannot be none/independent. Pure check — no disk is touched here.
_zfs_multi_validate_data_pools() {
  local data_pool_count="$1" i
  local data_name data_topology data_disk_count data_filesystem reason
  for ((i = 0; i < data_pool_count; i++)); do
    data_name="$(config_required ".data_pools[$i].name")"
    if ! reason="$(zfs_valid_pool_name "$data_name")"; then
      error "Data pool: ${reason}"
    fi
    data_topology="$(jsonc_strip "$CONFIG_FILE" \
      | jq -r ".data_pools[$i].topology // \"stripe\"")"
    data_disk_count="$(jsonc_strip "$CONFIG_FILE" \
      | jq "(.data_pools[$i].disks // []) | length")"
    # Filesystem-aware: a non-zfs pool carries a native topology (e.g. btrfs
    # raid1) the zfs vdev validator doesn't know; its validity is gated by
    # validation.sh, so the dispatch passes it through here (ADR 0043).
    data_filesystem="$(install_config_data_pool_filesystem "$i")"
    if ! reason="$(zfs_data_pool_topology_ok "$data_filesystem" \
                   "$data_topology" "$data_disk_count")"; then
      error "Data pool '${data_name}': ${reason}"
    fi
    _zfs_multi_validate_owners "Data pool '${data_name}'" \
      "$(install_config_data_pool_owners "$i" | awk '{ printf "%s ", $0 }')"
  done
}

# _zfs_multi_validate_first_duplicate — the first line (in sorted order) that
# stdin repeats; nothing when every line is unique.
_zfs_multi_validate_first_duplicate() {
  sort | awk 'seen && $0 == previous { print; exit }
              { previous = $0; seen = 1 }'
}

# Pool names must be unique across rpool + the Combined Data Pool (dpool) +
# every Standalone Data Pool, and no disk may serve two pools.
_zfs_multi_validate_unique_names() {
  local rpool_name duplicate_name
  rpool_name="$(config_required '.os_pool.pool_name')"
  duplicate_name="$( { printf '%s\n' "$rpool_name" dpool
                       jsonc_strip "$CONFIG_FILE" | jq -r '.data_pools[].name'
                     } | _zfs_multi_validate_first_duplicate)"
  [[ -z "$duplicate_name" ]] \
    || error "Duplicate pool name '${duplicate_name}': names must be" \
      "unique across rpool, dpool, and all data_pools."

}

# Disk reuse across OS pool, storage groups, and data pools — checked on every
# multi layout, not only with data pools (an OS disk reused by a storage group
# had its fresh partitions zapped).
_zfs_multi_validate_unique_disks() {
  local data_disk
  data_disk="$(jsonc_strip "$CONFIG_FILE" | jq -r '
    [ (.os_pool.disks // [])[],
      (.storage_groups[]?.disks // [])[],
      (.data_pools[]?.disks // [])[] ] | .[]' \
    | _zfs_multi_validate_first_duplicate)"
  [[ -z "$data_disk" ]] \
    || error "Disk '${data_disk}' is used in more than one" \
    "place (OS pool / storage group / data pool)."
}

# Mount rules over all declared storage mounts (storage groups + data pools,
# the latter defaulting to /data/<name>). None may shadow a reserved OS path;
# no two may claim the same exact mountpoint. Nested mounts (/data +
# /data/tank0) are fine — only exact dups are rejected.
_zfs_multi_validate_mounts() {
  local mounts=() mountpoint duplicate_mount
  while IFS= read -r mountpoint; do
    [[ -n "$mountpoint" ]] && mounts+=("$mountpoint")
  done < <(jsonc_strip "$CONFIG_FILE" | jq -r '
    [ (.storage_groups[]? | .mount // empty),
      (.data_pools[]? | .mount // ("/data/" + .name)) ] | .[]')
  for mountpoint in "${mounts[@]}"; do
    ! _zfs_multi_validate_mount_is_reserved "$mountpoint" \
      || error "Mountpoint '${mountpoint}' is reserved for the OS —" \
               "choose another."
  done
  duplicate_mount="$(printf '%s\n' "${mounts[@]}" \
    | _zfs_multi_validate_first_duplicate)"
  [[ -z "$duplicate_mount" ]] \
    || error "Mountpoint '${duplicate_mount}' is claimed by more than" \
      "one pool."
}

# Every data-pool disk must exist before any destructive op (typo fails
# safely). Last, so the name/topology/mount errors above surface first.
_zfs_multi_validate_data_disks_exist() {
  local data_pool_count="$1" i data_name disk
  for ((i = 0; i < data_pool_count; i++)); do
    data_name="$(config_required ".data_pools[$i].name")"
    while IFS= read -r disk; do
      layout_disk_exists "$disk" \
        || error "Data pool '${data_name}' disk not found: $disk"
    done < <(jsonc_strip "$CONFIG_FILE" | jq -r ".data_pools[$i].disks[]?")
  done
}

