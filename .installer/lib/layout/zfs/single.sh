#!/usr/bin/env bash
# =============================================================================
# lib/layout/zfs/single.sh — Single-disk install layout
# =============================================================================
# Sourced by 03-install.sh when INSTALL_MODE=single.
# Requires: lib/common.sh (for part_name), lib/zfs/pools.sh (for zfs_create_pool,
#           zfs_create_os_datasets, zfs_ram_gib) already sourced.
#
# Provides:
#   layout_calculate_single_disk — computes partition sizes,
#                                  prints layout table
#   layout_partition_single_disk         — wipes disk, creates 3 GPT partitions
#   layout_create_single_pools           — creates rpool (OS) and dpool (storage)
#   layout_mount_single_esp              — mounts the ESP into MOUNT_ROOT
#   layout_validate       — seam: validates single-disk config inputs
#   _layout_plan_mode     — plan hook (for layout_plan in plan.sh): wraps
#                           layout_calculate_single_disk + publishes pool names
#   _layout_os_disks      — plan hook: the single OS disk (for ESP resolution)
#   layout_partition      — seam: wraps layout_partition_single_disk
#   layout_create_pools   — seam: wraps layout_create_single_pools
#   layout_mount_esp      — seam: wraps layout_mount_single_esp
#
# INTERNAL STATE (do not reference outside this module):
#   _LAYOUT_IMPL_DISK       — target disk device path
#   _LAYOUT_IMPL_ESP_PART   — partition 1 (ESP, FAT32)
#   _LAYOUT_IMPL_OS_PART    — partition 2 (ZFS rpool)
#   _LAYOUT_IMPL_STOR_PART  — partition 3 (ZFS dpool)
#   _LAYOUT_IMPL_OS_SECTORS — size of the OS partition in 512-byte sectors
# =============================================================================

# shellcheck source=./common.sh
source "${BASH_SOURCE[0]%/*}/common.sh"

_LAYOUT_IMPL_DISK=""
_LAYOUT_IMPL_ESP_PART=""
_LAYOUT_IMPL_OS_PART=""
_LAYOUT_IMPL_STOR_PART=""
_LAYOUT_IMPL_OS_SECTORS=0

# =============================================================================
# LAYOUT CALCULATION
# =============================================================================

# Determines the OS and storage partition sizes, validates the disk has
# enough space, and prints the layout table.
#
# OS partition size = max of three candidates:
#   floor      = 40 GiB  (absolute minimum for a functional Arch install)
#   ram-based  = swap_gib + 30 GiB  (accommodates full swap + OS overhead)
#   percentage = 20% of disk  (scales naturally with larger disks)
#
# Storage partition = remainder after ESP + OS partition.
layout_calculate_single_disk() {
  section "Calculating Single-Disk Layout"

  _LAYOUT_IMPL_DISK="$(config_required '.disk' 'disk')"
  layout_disk_exists "$_LAYOUT_IMPL_DISK" \
    || error "Disk not found: $_LAYOUT_IMPL_DISK"

  # Use blockdev --getsize64 (bytes) for precision — avoids the truncation
  # error from sector-based math on disks that are not exact GiB multiples.
  # Virtual disks from virt-manager are often 1-2 MB short of a round GiB.
  local total_bytes ram
  total_bytes="$(blockdev --getsize64 "$_LAYOUT_IMPL_DISK")"
  local total_mib=$((total_bytes / 1024 / 1024))
  local total_gib=$((total_mib / 1024))
  ram="$(zfs_ram_gib)"
  info "Disk: $_LAYOUT_IMPL_DISK —" \
       "${total_mib} MiB (${total_gib} GiB)  |  RAM: ${ram} GiB"

  # ESP size in MiB (parsed from config, default 512M). layout_parse_size_to_mib
  # (core) keeps sub-GiB precision — the shared helper the non-ZFS spine
  # already uses, instead of a private re-implementation of the M/G case.
  local esp_size esp_mib
  esp_size="$(layout_resolve_esp_size)"
  esp_mib="$(layout_parse_size_to_mib "$esp_size")"

  # Usable MiB after ESP and 1 MiB alignment gaps (GPT header, partition gaps)
  local align_mib=2 # 1 MiB at start + 1 MiB guard at end
  local usable_mib=$((total_mib - esp_mib - align_mib))

  local swap_gib os_gib
  _zfs_single_resolve_swap_gib swap_gib "$ram" "$total_gib"
  _zfs_single_resolve_os_gib os_gib "$swap_gib" "$usable_mib"
  _zfs_single_check_sizes "$os_gib" "$usable_mib"

  # OS partition size in sectors for sgdisk (uses 512-byte sectors)
  _LAYOUT_IMPL_OS_SECTORS=$((os_gib * 1024 * 1024 * 1024 / 512))

  _zfs_single_print_layout "$total_mib" "$esp_size" "$os_gib" "$swap_gib" \
    "$(( (usable_mib - os_gib * 1024) / 1024 ))"
}

# _zfs_single_resolve_swap_gib <out-var> <ram_gib> <disk_gib> — the swap size
# in GiB: configured, or RAM × 2 capped to a quarter of a small disk.
_zfs_single_resolve_swap_gib() {
  local __swap_variable="$1" ram="$2" total_gib="$3" configured __swap_gib
  configured="$(config_optional '.options.swap_size')"
  if [[ -n "$configured" && "$configured" != "auto" ]]; then
    __swap_gib="$(layout_parse_size_to_gib "$configured")"
    info "Swap: ${__swap_gib} GiB  (from config)"
    printf -v "$__swap_variable" '%s' "$__swap_gib"
    return 0
  fi
  __swap_gib=$((ram * 2))
  # Cap swap to 25% of disk for small disks so the OS still fits
  local swap_cap=$((total_gib / 4))
  ((swap_cap < 2)) && swap_cap=2
  if ((__swap_gib > swap_cap)); then
    warn "Swap auto (${__swap_gib}G = RAM×2) capped to ${swap_cap}G" \
         "on this small disk."
    __swap_gib=$swap_cap
  fi
  info "Swap: ${__swap_gib} GiB  (auto)"
  printf -v "$__swap_variable" '%s' "$__swap_gib"
}

# _zfs_single_resolve_os_gib <out-var> <swap_gib> <usable_mib> — the OS
# partition in GiB: configured, or the largest of three candidates (never more
# than 90% of usable space, so there is always room for a storage partition).
_zfs_single_resolve_os_gib() {
  local __os_variable="$1" swap_gib="$2" usable_mib="$3" configured __os_gib
  configured="$(config_optional '.os_size')"
  if [[ -n "$configured" && "$configured" != "auto" ]]; then
    __os_gib="$(layout_parse_size_to_gib "$configured")"
    info "OS size: ${__os_gib} GiB  (from config)"
    printf -v "$__os_variable" '%s' "$__os_gib"
    return 0
  fi
  local floor=20                              # absolute minimum in GiB
  local ram_based=$((swap_gib + 20))          # swap + OS headroom
  local percent_gib=$((usable_mib * 80 / 100 / 1024)) # 80% of usable space
  # Note: 80% gives ~31G on a 40G disk — enough for KDE + base + headroom.
  # Storage pool gets the remaining 20% (~8G) for user data.

  __os_gib=$floor
  ((ram_based > __os_gib)) && __os_gib=$ram_based
  ((percent_gib > __os_gib)) && __os_gib=$percent_gib

  # Hard cap: never claim more than 90% of usable MiB
  local os_cap_mib=$((usable_mib * 90 / 100))
  local os_cap_gib=$((os_cap_mib / 1024))
  ((__os_gib > os_cap_gib && os_cap_gib > 0)) && __os_gib=$os_cap_gib

  info "OS size (auto): floor=${floor}G ram-based=${ram_based}G" \
       "80%=$((usable_mib * 80 / 100 / 1024))G" \
       "→ ${__os_gib}G (cap: ${os_cap_gib}G)"
  printf -v "$__os_variable" '%s' "$__os_gib"
}

# _zfs_single_check_sizes <os_gib> <usable_mib> — abort when the OS partition
# leaves no useful storage partition, or is itself too small.
_zfs_single_check_sizes() {
  local os_gib="$1" usable_mib="$2"
  local os_mib=$((os_gib * 1024))
  local storage_mib=$((usable_mib - os_mib))

  if ((os_mib >= usable_mib)); then
    error "OS partition (${os_gib} GiB) leaves no room for storage on this disk.
  Disk usable space: $((usable_mib / 1024)) GiB (after ESP and alignment).
  Fix: use a larger disk, or set a smaller 'os_size' in install.json."
  fi

  if ((storage_mib < 512)); then
    error "Storage partition would be only ${storage_mib} MiB" \
          "— too small to be useful.
  Disk usable space: $((usable_mib / 1024)) GiB  |  OS: ${os_gib} GiB
  Fix: use a larger disk, or set a smaller 'os_size' in install.json."
  fi

  if ((os_gib < 15)); then
    error "OS partition (${os_gib} GiB) is too small for Arch Linux + ZFS.
  Minimum recommended: 20 GiB. Use a larger disk."
  fi
}

_zfs_single_print_layout() {
  local total_mib="$1" esp_size="$2" os_gib="$3" swap_gib="$4"
  local storage_gib="$5"
  echo ""
  echo -e "  ${BOLD}Partition layout — $_LAYOUT_IMPL_DISK" \
          "(${total_mib} MiB):${NC}"
  printf "    %-5s  %-14s  %s\n" "Part" "Size" "Purpose"
  printf "    %-5s  %-14s  %s\n" "----" "--------------" "-------"
  printf "    %-5s  %-14s  %s\n" "p1" "${esp_size}" \
    "EFI System Partition (FAT32)"
  printf "    %-5s  %-14s  %s\n" "p2" "${os_gib} GiB" \
    "ZFS rpool  —  / /home /var swap(${swap_gib}G)"
  printf "    %-5s  %-14s  %s\n" "p3" "~${storage_gib} GiB" \
    "ZFS dpool  —  /data"
  echo ""
}

# =============================================================================
# PARTITIONING
# =============================================================================

layout_partition_single_disk() {
  section "Partitioning Single Disk"
  warn "ALL DATA ON $_LAYOUT_IMPL_DISK WILL BE DESTROYED."
  confirm "Confirm partitioning?"

  local esp_size
  esp_size="$(layout_resolve_esp_size)"

  # Wipe + zap + create the ESP (partition 1) — shared with the multi ritual.
  layout_zfs_partition_esp_start "$_LAYOUT_IMPL_DISK" "$esp_size"

  # GPT partition layout adds the two ZFS pool members:
  #   2  ZFS OS pool           (type bf00 = Solaris/ZFS)
  #   3  ZFS storage pool      (type bf00)
  sgdisk -n2:0:+"${_LAYOUT_IMPL_OS_SECTORS}s" -t2:bf00 \
    -c2:"ZFS rpool" "$_LAYOUT_IMPL_DISK"
  sgdisk -n3:0:0 -t3:bf00 -c3:"ZFS dpool" "$_LAYOUT_IMPL_DISK"

  # Re-probe so the kernel sees the new partition table
  partprobe "$_LAYOUT_IMPL_DISK"
  sleep 2

  _LAYOUT_IMPL_ESP_PART="$(part_name "$_LAYOUT_IMPL_DISK" 1)"
  _LAYOUT_IMPL_OS_PART="$(part_name "$_LAYOUT_IMPL_DISK" 2)"
  _LAYOUT_IMPL_STOR_PART="$(part_name "$_LAYOUT_IMPL_DISK" 3)"

  # LAYOUT_ESP_PARTS is published by layout_plan (ADR 0034); partitioning just
  # creates and formats the partitions whose paths the plan already resolved.
  mkfs.fat -F32 -n EFI "$_LAYOUT_IMPL_ESP_PART"
  info "Partitioned:"
  info "  ESP     → $_LAYOUT_IMPL_ESP_PART"
  info "  rpool   → $_LAYOUT_IMPL_OS_PART"
  info "  dpool   → $_LAYOUT_IMPL_STOR_PART"
}

# =============================================================================
# ZFS POOL CREATION
# =============================================================================

layout_create_single_pools() {
  section "Creating ZFS Pools (single-disk)"
  zfs_encryption_options

  local root_pool data_pool ashift mountpoint
  root_pool="$(install_config_os_pool_name)"
  data_pool="$(install_config_storage_pool_name)"
  ashift="$(install_config_ashift)"
  mountpoint="$(install_config_storage_mount)"

  # rpool — single partition, no RAID
  zfs_create_pool "${root_pool}" "${ashift}" "${_LAYOUT_IMPL_OS_PART}"
  zfs_create_os_datasets "${root_pool}"

  # dpool — the remaining partition; one dataset at the configured mount
  zfs_create_pool "${data_pool}" "${ashift}" "${_LAYOUT_IMPL_STOR_PART}"
  zfs create -o mountpoint="${mountpoint}" "${data_pool}/storage"
  info "dpool '${data_pool}' → ${mountpoint}"
}

# =============================================================================
# ESP MOUNTING
# =============================================================================

layout_mount_single_esp() {
  section "Mounting ESP"
  mkdir -p "${MOUNT_ROOT}/boot/efi"
  mount "$_LAYOUT_IMPL_ESP_PART" "${MOUNT_ROOT}/boot/efi"
  info "ESP: $_LAYOUT_IMPL_ESP_PART → /boot/efi"
}

# =============================================================================
# LAYOUT INTERFACE (called by 03-install.sh)
# =============================================================================

layout_validate() {
  layout_enter_phase validate
  layout_validate_esp_size
  local disk
  disk="$(config_required '.disk' 'disk')"
  layout_disk_exists "$disk" || error "Single disk not found: $disk"
  layout_exit_phase validate
}

# Mode hooks for the unified layout_plan (plan.sh). Phase bracketing, ESP
# resolution and the plan contract are handled there.
_layout_plan_mode() {
  layout_calculate_single_disk
  # Publish the pool-name record (consumed by chroot.sh, finalize.sh).
  # shellcheck disable=SC2034 # consumed by chroot.sh / finalize.sh
  LAYOUT_OS_POOL_NAME="$(config_optional .os_pool_name)"
  LAYOUT_OS_POOL_NAME="${LAYOUT_OS_POOL_NAME:-rpool}"
  local _data_pool_name
  _data_pool_name="$(config_optional .storage_pool_name)"
  # shellcheck disable=SC2034 # consumed by finalize.sh
  LAYOUT_DATA_POOL_NAMES=("${_data_pool_name:-dpool}")
}

# The single OS disk that receives the ESP. layout_calculate_single_disk (run by
# _layout_plan_mode) has already set _LAYOUT_IMPL_DISK by the time plan.sh asks.
_layout_os_disks() { printf '%s\n' "$_LAYOUT_IMPL_DISK"; }
layout_partition() {
  layout_enter_phase partition
  layout_partition_single_disk
  layout_verify_partition_contract
  layout_exit_phase partition
}
layout_create_pools() {
  layout_enter_phase pools
  layout_create_single_pools
  layout_exit_phase pools
}
layout_mount_esp() {
  layout_enter_phase esp
  layout_mount_single_esp
  layout_exit_phase esp
}
