#!/usr/bin/env bash
# =============================================================================
# lib/layout-single.sh — Single-disk install layout
# =============================================================================
# Sourced by 03-install.sh when INSTALL_MODE=single.
# Requires: lib/common.sh (for part_name), lib/zfs-pools.sh (for _zpool_create,
#           _create_os_datasets, ram_gib) already sourced.
#
# Provides:
#   calculate_single_disk_layout — computes partition sizes,
#                                  prints layout table
#   partition_single_disk         — wipes disk, creates 3 GPT partitions
#   create_single_pools           — creates rpool (OS) and dpool (storage)
#   mount_single_esp              — mounts the ESP into MOUNT_ROOT
#   layout_validate       — seam: validates single-disk config inputs
#   layout_plan           — seam: wraps calculate_single_disk_layout
#   layout_partition      — seam: wraps partition_single_disk
#   layout_create_pools   — seam: wraps create_single_pools
#   layout_mount_esp      — seam: wraps mount_single_esp
#
# INTERNAL STATE (do not reference outside this module):
#   _LAYOUT_IMPL_DISK       — target disk device path
#   _LAYOUT_IMPL_ESP_PART   — partition 1 (ESP, FAT32)
#   _LAYOUT_IMPL_OS_PART    — partition 2 (ZFS rpool)
#   _LAYOUT_IMPL_STOR_PART  — partition 3 (ZFS dpool)
#   _LAYOUT_IMPL_OS_SECTORS — size of the OS partition in 512-byte sectors
# =============================================================================

# shellcheck source=./layout-common.sh
source "${BASH_SOURCE[0]%/*}/layout-common.sh"

_LAYOUT_IMPL_DISK=""
_LAYOUT_IMPL_ESP_PART=""
_LAYOUT_IMPL_OS_PART=""
_LAYOUT_IMPL_STOR_PART=""
_LAYOUT_IMPL_OS_SECTORS=0

# =============================================================================
# LAYOUT CALCULATION
# =============================================================================

calculate_single_disk_layout() {
  # Determines the OS and storage partition sizes, validates the disk has
  # enough space, and prints the layout table.
  #
  # OS partition size = max of three candidates:
  #   floor      = 40 GiB  (absolute minimum for a functional Arch install)
  #   ram-based  = swap_gib + 30 GiB  (accommodates full swap + OS overhead)
  #   percentage = 20% of disk  (scales naturally with larger disks)
  #
  # Storage partition = remainder after ESP + OS partition.

  section "Calculating Single-Disk Layout"

  _LAYOUT_IMPL_DISK="$(cfg '.disk' 'disk')"
  [[ -b "$_LAYOUT_IMPL_DISK" ]] || error "Disk not found: $_LAYOUT_IMPL_DISK"

  # Use blockdev --getsize64 (bytes) for precision — avoids the truncation
  # error from sector-based math on disks that are not exact GiB multiples.
  # Virtual disks from virt-manager are often 1-2 MB short of a round GiB.
  local total_bytes
  total_bytes="$(blockdev --getsize64 "$_LAYOUT_IMPL_DISK")"
  local total_mib=$((total_bytes / 1024 / 1024))
  local total_gib=$((total_mib / 1024))
  local ram
  ram="$(ram_gib)"
  info "Disk: $_LAYOUT_IMPL_DISK —" \
       "${total_mib} MiB (${total_gib} GiB)  |  RAM: ${ram} GiB"

  # ESP size in MiB (parsed from config, default 512M)
  local esp_sz
  esp_sz="$(layout_resolve_esp_size)"
  local esp_mib
  # parse_size_to_gib rounds to whole GiB; handle sub-GiB ESP directly
  local esp_upper esp_digits
  esp_upper="${esp_sz^^}"
  esp_digits="${esp_upper//[^0-9]/}"
  case "$esp_upper" in
  *M | *MIB)
    esp_mib="$esp_digits"
    ;;
  *G | *GIB) esp_mib=$((esp_digits * 1024)) ;;
  *)         esp_mib=$(( $(parse_size_to_gib "$esp_sz") * 1024 )) ;;
  esac

  # Usable MiB after ESP and 1 MiB alignment gaps (GPT header, partition gaps)
  local align_mib=2 # 1 MiB at start + 1 MiB guard at end
  local usable_mib=$((total_mib - esp_mib - align_mib))

  # ── Swap size ─────────────────────────────────────────────────────────────
  local cfg_swap
  cfg_swap="$(cfgo '.options.swap_size')"
  local swap_gib
  if [[ -z "$cfg_swap" || "$cfg_swap" == "auto" ]]; then
    swap_gib=$((ram * 2))
    # Cap swap to 25% of disk for small disks so the OS still fits
    local swap_cap=$((total_gib / 4))
    ((swap_cap < 2)) && swap_cap=2
    if ((swap_gib > swap_cap)); then
      warn "Swap auto (${swap_gib}G = RAM×2) capped to ${swap_cap}G" \
           "on this small disk."
      swap_gib=$swap_cap
    fi
    info "Swap: ${swap_gib} GiB  (auto)"
  else
    swap_gib="$(parse_size_to_gib "$cfg_swap")"
    info "Swap: ${swap_gib} GiB  (from config)"
  fi

  # ── OS partition size ─────────────────────────────────────────────────────
  local cfg_os
  cfg_os="$(cfgo '.os_size')"
  local os_gib
  if [[ -z "$cfg_os" || "$cfg_os" == "auto" ]]; then
    # Three candidates — pick the largest, but never exceed 85% of usable space
    # so there is always room for a storage partition.
    local floor=20                              # absolute minimum in GiB
    local ram_based=$((swap_gib + 20))          # swap + OS headroom
    local pct=$((usable_mib * 80 / 100 / 1024)) # 80% of usable space
    # Note: 80% gives ~31G on a 40G disk — enough for KDE + base + headroom.
    # Storage pool gets the remaining 20% (~8G) for user data.

    os_gib=$floor
    ((ram_based > os_gib)) && os_gib=$ram_based
    ((pct > os_gib)) && os_gib=$pct

    # Hard cap: never claim more than 90% of usable MiB
    local os_cap_mib=$((usable_mib * 90 / 100))
    local os_cap_gib=$((os_cap_mib / 1024))
    ((os_gib > os_cap_gib && os_cap_gib > 0)) && os_gib=$os_cap_gib

    info "OS size (auto): floor=${floor}G ram-based=${ram_based}G" \
         "80%=$((usable_mib * 80 / 100 / 1024))G" \
         "→ ${os_gib}G (cap: ${os_cap_gib}G)"
  else
    os_gib="$(parse_size_to_gib "$cfg_os")"
    info "OS size: ${os_gib} GiB  (from config)"
  fi

  # ── Sanity checks ─────────────────────────────────────────────────────────
  local os_mib=$((os_gib * 1024))
  local stor_mib=$((usable_mib - os_mib))
  local stor_gib=$((stor_mib / 1024))

  if ((os_mib >= usable_mib)); then
    error "OS partition (${os_gib} GiB) leaves no room for storage on this disk.
  Disk usable space: $((usable_mib / 1024)) GiB (after ESP and alignment).
  Fix: use a larger disk, or set a smaller 'os_size' in install.json."
  fi

  if ((stor_mib < 512)); then
    error "Storage partition would be only ${stor_mib} MiB" \
          "— too small to be useful.
  Disk usable space: $((usable_mib / 1024)) GiB  |  OS: ${os_gib} GiB
  Fix: use a larger disk, or set a smaller 'os_size' in install.json."
  fi

  if ((os_gib < 15)); then
    error "OS partition (${os_gib} GiB) is too small for Arch Linux + ZFS.
  Minimum recommended: 20 GiB. Use a larger disk."
  fi

  # OS partition size in sectors for sgdisk (uses 512-byte sectors)
  _LAYOUT_IMPL_OS_SECTORS=$((os_mib * 1024 * 1024 / 512))

  # ── Layout table ──────────────────────────────────────────────────────────
  echo ""
  echo -e "  ${BOLD}Partition layout — $_LAYOUT_IMPL_DISK" \
          "(${total_mib} MiB):${NC}"
  printf "    %-5s  %-14s  %s\n" "Part" "Size" "Purpose"
  printf "    %-5s  %-14s  %s\n" "----" "--------------" "-------"
  printf "    %-5s  %-14s  %s\n" "p1" "${esp_sz}" "EFI System Partition (FAT32)"
  printf "    %-5s  %-14s  %s\n" "p2" "${os_gib} GiB" \
    "ZFS rpool  —  / /home /var swap(${swap_gib}G)"
  printf "    %-5s  %-14s  %s\n" "p3" "~${stor_gib} GiB" "ZFS dpool  —  /data"
  echo ""
}

# =============================================================================
# PARTITIONING
# =============================================================================

partition_single_disk() {
  section "Partitioning Single Disk"
  warn "ALL DATA ON $_LAYOUT_IMPL_DISK WILL BE DESTROYED."
  confirm "Confirm partitioning?"

  local esp_sz
  esp_sz="$(layout_resolve_esp_size)"

  # Wipe all existing signatures and partition tables
  wipefs -af "$_LAYOUT_IMPL_DISK"
  sgdisk --zap-all "$_LAYOUT_IMPL_DISK"

  # GPT partition layout:
  #   1  EFI System Partition  (type ef00 = EFI, FAT32)
  #   2  ZFS OS pool           (type bf00 = Solaris/ZFS)
  #   3  ZFS storage pool      (type bf00)
  sgdisk -n1:0:+"${esp_sz}" -t1:ef00 -c1:"EFI System" "$_LAYOUT_IMPL_DISK"
  sgdisk -n2:0:+"${_LAYOUT_IMPL_OS_SECTORS}s" -t2:bf00 \
    -c2:"ZFS rpool" "$_LAYOUT_IMPL_DISK"
  sgdisk -n3:0:0 -t3:bf00 -c3:"ZFS dpool" "$_LAYOUT_IMPL_DISK"

  # Re-probe so the kernel sees the new partition table
  partprobe "$_LAYOUT_IMPL_DISK"
  sleep 2

  _LAYOUT_IMPL_ESP_PART="$(part_name "$_LAYOUT_IMPL_DISK" 1)"
  _LAYOUT_IMPL_OS_PART="$(part_name "$_LAYOUT_IMPL_DISK" 2)"
  _LAYOUT_IMPL_STOR_PART="$(part_name "$_LAYOUT_IMPL_DISK" 3)"

  # ── Publish layout state record ───────────────────────────────────────────
  # shellcheck disable=SC2034 # consumed by chroot.sh / finalize.sh
  LAYOUT_ESP_PARTS=("$_LAYOUT_IMPL_ESP_PART")

  mkfs.fat -F32 -n EFI "$_LAYOUT_IMPL_ESP_PART"
  info "Partitioned:"
  info "  ESP     → $_LAYOUT_IMPL_ESP_PART"
  info "  rpool   → $_LAYOUT_IMPL_OS_PART"
  info "  dpool   → $_LAYOUT_IMPL_STOR_PART"
}

# =============================================================================
# ZFS POOL CREATION
# =============================================================================

create_single_pools() {
  section "Creating ZFS Pools (single-disk)"
  build_enc_opts

  local rp dp ashift mnt
  rp="$(install_config_os_pool_name)"
  dp="$(install_config_storage_pool_name)"
  ashift="$(install_config_ashift)"
  mnt="$(install_config_storage_mount)"

  # rpool — single partition, no RAID
  _zpool_create "${rp}" "${ashift}" "${_LAYOUT_IMPL_OS_PART}"
  _create_os_datasets "${rp}"

  # dpool — the remaining partition; one dataset at the configured mount
  _zpool_create "${dp}" "${ashift}" "${_LAYOUT_IMPL_STOR_PART}"
  zfs create -o mountpoint="${mnt}" "${dp}/storage"
  info "dpool '${dp}' → ${mnt}"
}

# =============================================================================
# ESP MOUNTING
# =============================================================================

mount_single_esp() {
  section "Mounting ESP"
  mkdir -p "${MOUNT_ROOT}/boot/efi"
  mount "$_LAYOUT_IMPL_ESP_PART" "${MOUNT_ROOT}/boot/efi"
  info "ESP: $_LAYOUT_IMPL_ESP_PART → /boot/efi"
}

# =============================================================================
# LAYOUT INTERFACE (called by 03-install.sh)
# =============================================================================

layout_validate() {
  _layout_enter_phase validate
  local d
  d="$(cfg '.disk' 'disk')"
  [[ -b "$d" ]] || error "Single disk not found: $d"
  _layout_exit_phase validate
}

layout_plan() {
  _layout_enter_phase plan
  calculate_single_disk_layout
  # Publish layout state record (consumed by chroot.sh, finalize.sh).
  # shellcheck disable=SC2034 # consumed by chroot.sh / finalize.sh
  LAYOUT_OS_POOL_NAME="$(cfgo .os_pool_name)"
  LAYOUT_OS_POOL_NAME="${LAYOUT_OS_POOL_NAME:-rpool}"
  # shellcheck disable=SC2034 # consumed by chroot.sh / finalize.sh
  LAYOUT_DATA_POOL_NAME="$(cfgo .storage_pool_name)"
  LAYOUT_DATA_POOL_NAME="${LAYOUT_DATA_POOL_NAME:-dpool}"
  _layout_verify_plan_contract
  _layout_exit_phase plan
}
layout_partition() {
  _layout_enter_phase partition
  partition_single_disk
  _layout_verify_partition_contract
  _layout_exit_phase partition
}
layout_create_pools() {
  _layout_enter_phase pools
  create_single_pools
  _layout_exit_phase pools
}
layout_mount_esp() {
  _layout_enter_phase esp
  mount_single_esp
  _layout_exit_phase esp
}
