#!/usr/bin/env bash
# =============================================================================
# lib/layout/zfs/multi.sh — Multi-disk install layout
# =============================================================================
# Sourced by 03-install.sh when INSTALL_MODE=multi.
# Requires: lib/common.sh (for part_name), lib/zfs/pools.sh (for zfs_create_pool,
#           zfs_vdev_spec, zfs_ram_gib) already sourced.
#
# Provides:
#   layout_resolve_os_topology          — determines rpool topology; prompts if needed
#   layout_resolve_storage_topologies   — determines dpool group topologies; prompts
#   layout_partition_os_disks_multi     — partitions OS disk(s)
#   layout_partition_storage_disks_multi— partitions storage group disk(s)
#   layout_create_multi_rpool           — creates rpool with resolved topology
#   layout_create_multi_data_pool           — creates dpool with all storage groups
#   layout_resolve_data_pools           — reads data_pools[] into internal state
#   layout_resolve_leftover_disks       — per-disk fold-vs-own-pool for topology=none
#   layout_partition_data_pools         — partitions Standalone Data Pool disk(s)
#   layout_create_data_pools            — creates each Standalone Data Pool + dataset
#   layout_mount_multi_esps             — mounts primary + secondary ESPs
#   layout_validate  — seam: validates os_pool + storage_groups inputs
#   _layout_plan_mode — plan hook (for layout_plan in plan.sh): wraps
#                     layout_resolve_os_topology; layout_resolve_data_pools;
#                     layout_resolve_storage_topologies; layout_resolve_leftover_disks
#   _layout_os_disks  — plan hook: ordered OS disks (for ESP resolution)
#   layout_partition — seam: wraps layout_partition_os_disks_multi;
#                     layout_partition_storage_disks_multi
#   layout_create_pools   — seam: wraps layout_create_multi_rpool; layout_create_multi_data_pool
#   layout_mount_esp      — seam: wraps layout_mount_multi_esps
#
# INTERNAL STATE (do not reference outside this module):
#   _LAYOUT_IMPL_ESP_PARTS[]         — ESP partitions on OS disks
#   _LAYOUT_IMPL_ZFS_PARTS[]         — ZFS partitions on OS disks (for rpool)
#   _LAYOUT_IMPL_OS_DISK          — chosen single OS disk (topology=none only)
#   _LAYOUT_IMPL_OS_TOPOLOGY      — resolved topology string
#   _LAYOUT_IMPL_LEFTOVER_DISKS[] — OS-list disks folded into dpool
#                                 (topology=none)
#   _LAYOUT_IMPL_STORAGE_PARTS[name]    — associative:
#                                         group name → "part1 part2 ..."
#   _LAYOUT_IMPL_TOPOLOGIES[]  — associative: group name → topology string
#   _LAYOUT_IMPL_DATA_POOL_NAMES[]  — ordered Standalone Data Pool names
#   _LAYOUT_IMPL_DATA_POOL_DISKS[]  — associative: pool name → "disk1 ..."
#   _LAYOUT_IMPL_DATA_POOL_TOPOLOGY[]   — associative: pool name → topology
#   _LAYOUT_IMPL_DATA_POOL_MOUNT[]  — associative: pool name → mountpoint
#   _LAYOUT_IMPL_DATA_POOL_ASHIFT[] — associative: pool name → ashift
#   _LAYOUT_IMPL_DATA_POOL_PARTS[]  — associative: pool name → "part1 ..."
# =============================================================================

# shellcheck source=./common.sh
source "${BASH_SOURCE[0]%/*}/common.sh"
# layout_create_data_pools dispatches each group through the Data Group Formatter seam.
declare -F data_formatter_source >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../dispatch.sh"

_LAYOUT_IMPL_ESP_PARTS=()
_LAYOUT_IMPL_ZFS_PARTS=()
_LAYOUT_IMPL_OS_DISK=""
_LAYOUT_IMPL_OS_TOPOLOGY=""
_LAYOUT_IMPL_LEFTOVER_DISKS=()
declare -gA _LAYOUT_IMPL_STORAGE_PARTS
declare -gA _LAYOUT_IMPL_TOPOLOGIES
# The Standalone Data Pool record + resolve/partition/create pipeline lives in
# the root-fs-agnostic orchestrator (lib/layout/data-pools.sh, sourced by core);
# this adapter's seam verbs call it, and the interactive leftover synthesis below
# appends to it via layout_add_data_pool.

# Out-param for layout_prompt_pool_name (mirrors PICK_RESULT house style).
POOL_NAME_RESULT=""

# Topology suggestion + resolution, and the topology=none leftover disks.
# shellcheck source=./multi-topology.sh
source "${BASH_SOURCE[0]%/*}/multi-topology.sh"
# layout_validate + its config checks.
# shellcheck source=./multi-validate.sh
source "${BASH_SOURCE[0]%/*}/multi-validate.sh"

# =============================================================================
# PARTITIONING
# =============================================================================

layout_partition_os_disks_multi() {
  section "Partitioning OS Disk(s)"
  local esp_size
  esp_size="$(layout_resolve_esp_size)"
  _LAYOUT_IMPL_ESP_PARTS=()
  _LAYOUT_IMPL_ZFS_PARTS=()

  # When topology=none, only the chosen disk goes into rpool
  local rpool_disks=()
  if [[ "$_LAYOUT_IMPL_OS_TOPOLOGY" == "none" ]]; then
    rpool_disks=("$_LAYOUT_IMPL_OS_DISK")
  else
    while IFS= read -r d; do rpool_disks+=("$d"); done \
      < <(jsonc "$CONFIG_FILE" | jq -r '.os_pool.disks[]')
  fi

  local disk
  for disk in "${rpool_disks[@]}"; do
    info "Partitioning OS disk: $disk"
    # Wipe + zap + create the ESP (partition 1) — shared with the single ritual.
    layout_zfs_partition_esp_start "$disk" "$esp_size"
    # p2 — ZFS rpool (rest of disk)
    sgdisk -n2:0:0 -t2:bf00 -c2:"ZFS rpool" "$disk"
    partprobe "$disk"
    _LAYOUT_IMPL_ESP_PARTS+=("$(part_name "$disk" 1)")
    _LAYOUT_IMPL_ZFS_PARTS+=("$(part_name "$disk" 2)")
  done

  layout_settle
  local i
  for i in "${!_LAYOUT_IMPL_ESP_PARTS[@]}"; do
    mkfs.fat -F32 -n "EFI$((i + 1))" "${_LAYOUT_IMPL_ESP_PARTS[$i]}"
    info "Formatted ESP $((i + 1)): ${_LAYOUT_IMPL_ESP_PARTS[$i]}"
  done
  # LAYOUT_ESP_PARTS is published by layout_plan (ADR 0034); partitioning just
  # creates and formats the partitions whose paths the plan already resolved.
}

layout_partition_storage_disks_multi() {
  section "Partitioning Storage Disk(s)"

  # Config-defined storage groups
  local storage_group
  storage_group="$(jsonc "$CONFIG_FILE" | jq '.storage_groups | length')"
  local i
  for ((i = 0; i < storage_group; i++)); do
    local name
    name="$(config_required ".storage_groups[$i].name")"
    local parts=()
    while IFS= read -r disk; do
      info "Partitioning storage disk: $disk  (group: ${name})"
      wipefs -af "$disk"
      sgdisk --zap-all "$disk"
      sgdisk -n1:0:0 -t1:bf00 -c1:"ZFS dpool-${name}" "$disk"
      partprobe "$disk"
      parts+=("$(part_name "$disk" 1)")
    done < <(jsonc "$CONFIG_FILE" | jq -r ".storage_groups[$i].disks[]")
    _LAYOUT_IMPL_STORAGE_PARTS["$name"]="${parts[*]}"
  done

  # Leftover OS disks (topology=none, 2+ OS disks listed)
  if ((${#_LAYOUT_IMPL_LEFTOVER_DISKS[@]} > 0)); then
    local lparts=()
    local disk
    for disk in "${_LAYOUT_IMPL_LEFTOVER_DISKS[@]}"; do
      info "Partitioning leftover OS disk → dpool: $disk"
      wipefs -af "$disk"
      sgdisk --zap-all "$disk"
      sgdisk -n1:0:0 -t1:bf00 -c1:"ZFS dpool-extra" "$disk"
      partprobe "$disk"
      lparts+=("$(part_name "$disk" 1)")
    done
    _LAYOUT_IMPL_STORAGE_PARTS["_leftover"]="${lparts[*]}"
  fi

  layout_settle
  info "Storage partitioning complete."
}

# =============================================================================
# ZFS POOL CREATION
# =============================================================================

layout_create_multi_rpool() {
  section "Creating OS Pool (rpool)"
  zfs_encryption_options

  local pool_name
  pool_name="$(config_required '.os_pool.pool_name')"
  local ashift; ashift="$(install_config_os_pool_ashift)"

  local vdev_spec
  vdev_spec="$(zfs_vdev_spec "${_LAYOUT_IMPL_OS_TOPOLOGY}" \
    "${_LAYOUT_IMPL_ZFS_PARTS[@]}")"

  info "Pool: ${pool_name}  topology: ${_LAYOUT_IMPL_OS_TOPOLOGY}"
  info "vdev: ${vdev_spec}"

  # SC2086 (intentional): vdev_spec must be word-split into multiple args
  # for zfs_create_pool (e.g. "mirror /dev/sda1 /dev/sdb1" → 3 args). Built
  # from controlled inputs in zfs_vdev_spec, so word-splitting is safe.
  # shellcheck disable=SC2086
  zfs_create_pool "${pool_name}" "${ashift}" $vdev_spec
  zfs_create_os_datasets "${pool_name}"
}

layout_create_multi_data_pool() {
  section "Creating Data Pool (dpool)"

  local storage_group_count has_leftover=false
  storage_group_count="$(jsonc "$CONFIG_FILE" | jq '.storage_groups | length')"
  [[ -v "_LAYOUT_IMPL_STORAGE_PARTS[_leftover]" ]] && has_leftover=true

  if ((storage_group_count == 0)) && ! $has_leftover; then
    info "No storage groups and no leftover disks — skipping dpool."
    return
  fi
  zfs_encryption_options

  # Collect vdev specs from all groups
  local all_vdevs=() i name parts leftover_topology
  for ((i = 0; i < storage_group_count; i++)); do
    name="$(config_required ".storage_groups[$i].name")"
    read -ra parts <<<"${_LAYOUT_IMPL_STORAGE_PARTS[$name]}"
    _zfs_multi_add_group_vdevs all_vdevs "$name" \
      "${_LAYOUT_IMPL_TOPOLOGIES[$name]:-stripe}" "${parts[@]}"
  done
  leftover_topology="${_LAYOUT_IMPL_TOPOLOGIES[_leftover]:-independent}"
  if $has_leftover; then
    read -ra parts <<<"${_LAYOUT_IMPL_STORAGE_PARTS[_leftover]}"
    _zfs_multi_add_group_vdevs all_vdevs _leftover "$leftover_topology" \
      "${parts[@]}"
  fi

  # Use the first storage group's ashift (all storage disks ideally match)
  local ashift; ashift="$(install_config_storage_group_ashift 0)"

  # SC2068 (intentional): all_vdevs holds pre-tokenised vdev spec elements
  # that must each become a separate argument to zpool create. Names are
  # internally generated so word-splitting is safe.
  # shellcheck disable=SC2068
  zfs_create_pool "dpool" "${ashift}" ${all_vdevs[@]}

  _zfs_multi_create_datasets "$storage_group_count" "$has_leftover" \
    "$leftover_topology"

  info "dpool created."
}

# _zfs_multi_create_datasets <group_count> <has_leftover> <leftover_topology>
# — dpool/DATA plus one dataset tree per storage group and the leftovers.
_zfs_multi_create_datasets() {
  local storage_group_count="$1" has_leftover="$2" leftover_topology="$3"
  local i name parts
  zfs create -o canmount=off -o mountpoint=none dpool/DATA

  # One dataset per config-defined group
  for ((i = 0; i < storage_group_count; i++)); do
    name="$(config_required ".storage_groups[$i].name")"
    read -ra parts <<<"${_LAYOUT_IMPL_STORAGE_PARTS[$name]}"
    _zfs_multi_create_group_datasets "dpool/DATA/${name}" \
      "$(config_required ".storage_groups[$i].mount")" \
      "${_LAYOUT_IMPL_TOPOLOGIES[$name]:-stripe}" "${#parts[@]}"
  done

  # Dataset(s) for leftover OS disks
  if $has_leftover; then
    read -ra parts <<<"${_LAYOUT_IMPL_STORAGE_PARTS[_leftover]}"
    _zfs_multi_create_group_datasets "dpool/DATA/extra" "/data/extra" \
      "$leftover_topology" "${#parts[@]}"
  fi
}

# _zfs_multi_add_group_vdevs <array-name> <group> <topology> <part>... —
# append the group's vdev spec tokens to the named array.
_zfs_multi_add_group_vdevs() {
  local -n __vdevs="$1"
  local group="$2" topology="$3" vdev_spec
  shift 3
  vdev_spec="$(zfs_vdev_spec "$topology" "$@")"
  # SC2206 (intentional): vdev_spec is a single string built from
  # zfs_vdev_spec output that we want word-split into separate vdev tokens
  # (e.g. "mirror /dev/sdb1 /dev/sdc1" → 3 array elements).
  # shellcheck disable=SC2206
  __vdevs+=($vdev_spec)
  info "  Group '${group}': ${topology}  [$*]"
}

# _zfs_multi_create_group_datasets <dataset> <mountpoint> <topology> <disks>
# — an independent group gets one child dataset per disk (each managed
# separately); any other topology one dataset.
_zfs_multi_create_group_datasets() {
  local dataset="$1" mountpoint="$2" topology="$3" disk_count="$4" disk
  if [[ "$topology" != "independent" ]]; then
    zfs create -o mountpoint="${mountpoint}" "${dataset}"
    info "  ${dataset} → ${mountpoint}"
    return 0
  fi
  zfs create -o canmount=off -o mountpoint=none "${dataset}"
  for ((disk = 1; disk <= disk_count; disk++)); do
    zfs create -o mountpoint="${mountpoint}/disk${disk}" \
      "${dataset}/disk${disk}"
    info "  ${dataset}/disk${disk} → ${mountpoint}/disk${disk}"
  done
}

# =============================================================================
# ESP MOUNTING
# =============================================================================

layout_mount_multi_esps() {
  section "Mounting ESP(s)"

  # Primary ESP (first OS disk) → /boot/efi
  mkdir -p "${MOUNT_ROOT}/boot/efi"
  mount "${_LAYOUT_IMPL_ESP_PARTS[0]}" "${MOUNT_ROOT}/boot/efi"
  info "Primary ESP: ${_LAYOUT_IMPL_ESP_PARTS[0]} → /boot/efi"

  # Secondary ESPs → /boot/efi1, /boot/efi2, ...
  local i
  for i in $(seq 1 $((${#_LAYOUT_IMPL_ESP_PARTS[@]} - 1))); do
    mkdir -p "${MOUNT_ROOT}/boot/efi${i}"
    mount "${_LAYOUT_IMPL_ESP_PARTS[$i]}" "${MOUNT_ROOT}/boot/efi${i}"
    info "Secondary ESP ${i}: ${_LAYOUT_IMPL_ESP_PARTS[$i]} → /boot/efi${i}"
  done
}

# Mode hooks for the unified layout_plan (plan.sh). Phase bracketing, ESP
# resolution and the plan contract are handled there.
_layout_plan_mode() {
  layout_resolve_os_topology
  # Declarative data_pools[] first, so interactive leftover naming can reject
  # collisions against them (uniqueness + default dataN numbering).
  layout_resolve_data_pools
  layout_resolve_storage_topologies
  layout_resolve_leftover_disks
  # Publish the pool-name record (consumed by chroot.sh, finalize.sh).
  # shellcheck disable=SC2034 # consumed by chroot.sh / finalize.sh
  LAYOUT_OS_POOL_NAME="$(config_required '.os_pool.pool_name')"
  # LAYOUT_DATA_POOL_NAMES: the Combined Data Pool (when storage groups or
  # folded leftovers exist) plus every Standalone Data Pool.
  # shellcheck disable=SC2034 # consumed by finalize.sh
  LAYOUT_DATA_POOL_NAMES=()
  local _storage_group_count
  _storage_group_count="$(jsonc "$CONFIG_FILE" | jq '.storage_groups | length')"
  if ((_storage_group_count > 0)) || ((${#_LAYOUT_IMPL_LEFTOVER_DISKS[@]} > 0)); then
    LAYOUT_DATA_POOL_NAMES+=("dpool")
  fi
  local _data_pool_name
  for _data_pool_name in "${_LAYOUT_IMPL_DATA_POOL_NAMES[@]}"; do
    LAYOUT_DATA_POOL_NAMES+=("$_data_pool_name")
  done
}

# Ordered OS disks that receive an ESP — primary first. topology=none installs
# onto the one chosen disk; otherwise every os_pool disk is mirrored/striped and
# each gets an ESP. layout_resolve_os_topology (run by _layout_plan_mode) has set the
# topology + chosen disk by the time plan.sh asks.
_layout_os_disks() {
  if [[ "$_LAYOUT_IMPL_OS_TOPOLOGY" == "none" ]]; then
    printf '%s\n' "$_LAYOUT_IMPL_OS_DISK"
  else
    jsonc "$CONFIG_FILE" | jq -r '.os_pool.disks[]'
  fi
}
layout_partition() {
  layout_enter_phase partition
  layout_partition_os_disks_multi
  layout_partition_storage_disks_multi
  layout_partition_data_pools
  layout_verify_partition_contract
  layout_exit_phase partition
}
layout_create_pools() {
  layout_enter_phase pools
  layout_create_multi_rpool
  layout_create_multi_data_pool
  layout_create_data_pools
  layout_exit_phase pools
}
layout_mount_esp() {
  layout_enter_phase esp
  layout_mount_multi_esps
  layout_exit_phase esp
}
