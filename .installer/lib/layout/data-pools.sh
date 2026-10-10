#!/usr/bin/env bash
# =============================================================================
# lib/layout/data-pools.sh — root-fs-agnostic Standalone Data Pool orchestrator
# =============================================================================
# The resolve → partition → create pipeline for Standalone Data Pools (ADR
# 0027/0043), lifted out of the ZFS multi Root Adapter so ANY root filesystem
# (zfs / btrfs / ext4 / xfs) can host `data_pools[]`. A data pool is disks +
# topology + its own filesystem; creation dispatches per-group through the Data
# Group Formatter seam (data_formatter_source <fs> → <fs>/data.sh), so this
# module never assumes the root — or the group — is ZFS.
#
# Each root adapter invokes the three verbs from its own seam:
#   layout_resolve_data_pools    — in the plan phase (reads data_pools[] → record)
#   layout_partition_data_pools  — in the partition phase (GPT-labels the pool disks)
#   layout_create_data_pools     — in the pools phase (formats each group via the seam)
# The ZFS multi adapter also appends interactively-synthesised leftover pools
# (topology=none fold-vs-own-pool) through layout_add_data_pool — that synthesis stays
# ZFS-multi-specific; the shared structure and creation path are here.
#
# Requires at call time: lib/common.sh (config_required/section/info/warn/error, part_name),
# lib/config/accessors.sh (install_config_data_pool_*), MOUNT_ROOT,
# INSTALLER_DIR.
# =============================================================================

# The Data Group Formatter dispatch (data_formatter_source) + the redundant-size
# warning helper. Guard-sourced so this module stands alone for any root fs.
declare -F data_formatter_source >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/dispatch.sh"
declare -F zfs_redundant_size_mismatch >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../zfs/pools.sh"

# ── The Standalone Data Pool record (populated by resolve + layout_add_data_pool) ───
# shellcheck disable=SC2034  # consumed across the layout module + pool-owners
_LAYOUT_IMPL_DATA_POOL_NAMES=()
declare -gA _LAYOUT_IMPL_DATA_POOL_DISKS
declare -gA _LAYOUT_IMPL_DATA_POOL_TOPOLOGY
declare -gA _LAYOUT_IMPL_DATA_POOL_MOUNT
declare -gA _LAYOUT_IMPL_DATA_POOL_ASHIFT
declare -gA _LAYOUT_IMPL_DATA_POOL_PARTS
# Per-group filesystem + encryption (ADR 0043): a Standalone Data Pool may pick
# its own filesystem (default the root's) and opt into encryption independently.
# zfs groups take the native path; ext4/xfs/btrfs dispatch to the non-ZFS Data
# Group Formatter (lib/layout/<fs>/data.sh).
declare -gA _LAYOUT_IMPL_DATA_POOL_FILESYSTEM
declare -gA _LAYOUT_IMPL_DATA_POOL_ENCRYPTION

layout_resolve_data_pools() {
  # Reads declarative data_pools[] into the internal data-pool structure
  # consumed by layout_partition_data_pools / layout_create_data_pools. Interactive
  # leftover-as-own-pool synthesis appends to the same structure (a later
  # slice); declarative and interactive pools share one creation path.
  local pool_count
  pool_count="$(install_config_data_pools_count)"
  ((pool_count > 0)) || return 0
  section "Resolving Standalone Data Pools"

  local i
  for ((i = 0; i < pool_count; i++)); do
    local name topology mount ashift filesystem encryption
    name="$(install_config_data_pool_name "$i")"
    topology="$(install_config_data_pool_topology "$i")"
    mount="$(install_config_data_pool_mount "$i")"
    ashift="$(install_config_data_pool_ashift "$i")"
    filesystem="$(install_config_data_pool_filesystem "$i")"
    encryption="$(install_config_data_pool_encryption "$i")"

    local disks=()
    while IFS= read -r d; do
      [[ -n "$d" ]] && disks+=("$d")
    done < <(install_config_data_pool_disks "$i")

    layout_add_data_pool "$name" "$topology" "$mount" "$ashift" "$filesystem" "$encryption" "${disks[@]}"
    info "Data pool '${name}': ${filesystem} ${topology}  [${disks[*]}] → ${mount}"

    # Non-fatal heads-up: a redundant pool over unequal disks caps usable
    # space to its smallest member (ADR 0027). Sizes from real disks here;
    # bytes drive the decision, the human string is for the message.
    local bytes=() human=() disk
    for disk in "${disks[@]}"; do
      bytes+=("$(lsblk -bdno SIZE "$disk" 2>/dev/null || echo 0)")
      human+=("$(lsblk -dno SIZE "$disk" 2>/dev/null || echo '?')")
    done
    if zfs_redundant_size_mismatch "$topology" "${bytes[@]}"; then
      local smallest_index=0 index
      for index in "${!bytes[@]}"; do
        ((bytes[index] < bytes[smallest_index])) && smallest_index="$index"
      done
      warn "Data pool '${name}' (${topology}) spans unequal-size disks —" \
        "usable space caps to ${human[$smallest_index]} (smallest member):"
      for index in "${!disks[@]}"; do
        warn "  ${disks[$index]}  (${human[$index]})"
      done
    fi
  done
}

layout_add_data_pool() {
  # Appends one pool to the internal data-pool structure consumed by
  # layout_partition_data_pools / layout_create_data_pools. Shared by the declarative and
  # interactive paths so both go through one creation path.
  # Usage: layout_add_data_pool <name> <topology> <mount> <ashift> <fs> <enc> <disk...>
  local name="$1" topology="$2" mount="$3" ashift="$4" filesystem="$5" encryption="$6"
  shift 6
  _LAYOUT_IMPL_DATA_POOL_NAMES+=("$name")
  _LAYOUT_IMPL_DATA_POOL_DISKS["$name"]="$*"
  _LAYOUT_IMPL_DATA_POOL_TOPOLOGY["$name"]="$topology"
  _LAYOUT_IMPL_DATA_POOL_MOUNT["$name"]="$mount"
  _LAYOUT_IMPL_DATA_POOL_ASHIFT["$name"]="$ashift"
  _LAYOUT_IMPL_DATA_POOL_FILESYSTEM["$name"]="$filesystem"
  _LAYOUT_IMPL_DATA_POOL_ENCRYPTION["$name"]="$encryption"
}

layout_partition_data_pools() {
  ((${#_LAYOUT_IMPL_DATA_POOL_NAMES[@]} > 0)) || return 0
  section "Partitioning Standalone Data Pool Disk(s)"

  local name
  for name in "${_LAYOUT_IMPL_DATA_POOL_NAMES[@]}"; do
    local disks=()
    read -ra disks <<<"${_LAYOUT_IMPL_DATA_POOL_DISKS[$name]}"
    # GPT type by filesystem: bf00 (Solaris/ZFS) for a zfs pool, 8300 (Linux
    # filesystem) for ext4/xfs/btrfs — LUKS lives inside an 8300 partition too.
    local filesystem="${_LAYOUT_IMPL_DATA_POOL_FILESYSTEM[$name]:-zfs}" ptype label
    if [[ "$filesystem" == "zfs" ]]; then
      ptype=bf00 label="ZFS ${name}"
    else
      ptype=8300 label="${filesystem} ${name}"
    fi
    local parts=()
    local disk
    for disk in "${disks[@]}"; do
      info "Partitioning data-pool disk: $disk  (pool: ${name}, ${filesystem})"
      wipefs -af "$disk"
      sgdisk --zap-all "$disk"
      sgdisk -n1:0:0 -t1:"$ptype" -c1:"$label" "$disk"
      partprobe "$disk"
      parts+=("$(part_name "$disk" 1)")
    done
    _LAYOUT_IMPL_DATA_POOL_PARTS["$name"]="${parts[*]}"
  done

  sleep 2
  info "Standalone data pool partitioning complete."
}

layout_create_data_pools() {
  ((${#_LAYOUT_IMPL_DATA_POOL_NAMES[@]} > 0)) || return 0
  section "Creating Standalone Data Pool(s)"

  local name
  for name in "${_LAYOUT_IMPL_DATA_POOL_NAMES[@]}"; do
    local filesystem="${_LAYOUT_IMPL_DATA_POOL_FILESYSTEM[$name]:-zfs}"
    local topology="${_LAYOUT_IMPL_DATA_POOL_TOPOLOGY[$name]:-stripe}"
    local mount="${_LAYOUT_IMPL_DATA_POOL_MOUNT[$name]}"
    local encryption="${_LAYOUT_IMPL_DATA_POOL_ENCRYPTION[$name]:-false}"
    local parts=()
    read -ra parts <<<"${_LAYOUT_IMPL_DATA_POOL_PARTS[$name]}"

    # Uniform per-group dispatch (ADR 0043): every group — zfs or not — goes to
    # its Data Group Formatter leaf (data_formatter_source <fs> → <fs>/data.sh)
    # via the shared data_formatter_create_group seam. The ZFS leaf creates a zpool (reading
    # ashift from the record); ext4/xfs/btrfs mkfs a partition. The topology arg
    # matters to zfs + btrfs (ext4/xfs are single-disk).
    # shellcheck source=/dev/null
    source "$(data_formatter_source "$INSTALLER_DIR" "$filesystem")"
    data_formatter_create_group "$filesystem" "$name" "$encryption" "$mount" "$topology" "${parts[@]}"
  done

  info "Standalone data pool(s) created."
}
