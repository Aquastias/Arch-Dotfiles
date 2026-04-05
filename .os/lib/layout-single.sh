#!/usr/bin/env bash
# =============================================================================
# lib/layout-single.sh — Single-disk install layout
# =============================================================================
# Sourced by 03-install.sh when INSTALL_MODE=single.
# Requires: lib/common.sh, lib/zfs-pools.sh already sourced.
#
# Provides:
#   calculate_single_disk_layout  — computes partition sizes, prints layout table
#   partition_single_disk         — wipes disk, creates 3 GPT partitions
#   create_single_pools           — creates rpool (OS) and dpool (storage)
#   mount_single_esp              — mounts the ESP into MOUNT_ROOT
#
# GLOBALS SET:
#   SINGLE_DISK       — target disk device path
#   SINGLE_ESP_PART   — partition 1 (ESP, FAT32)
#   SINGLE_OS_PART    — partition 2 (ZFS rpool)
#   SINGLE_STOR_PART  — partition 3 (ZFS dpool)
#   SINGLE_OS_SECTORS — size of the OS partition in 512-byte sectors
# =============================================================================

SINGLE_DISK=""
SINGLE_ESP_PART=""
SINGLE_OS_PART=""
SINGLE_STOR_PART=""
SINGLE_OS_SECTORS=0

# =============================================================================
# SIZE HELPERS
# =============================================================================

parse_size_to_gib() {
  # Converts a human-readable size string to integer GiB (rounded up).
  # Accepts: "512M", "80G", "2T"  (case-insensitive)
  local raw="${1^^}"
  local num="${raw//[^0-9]/}"
  local unit="${raw//[0-9]/}"
  case "$unit" in
  M | MIB) echo $(((num + 1023) / 1024)) ;;
  G | GIB) echo "$num" ;;
  T | TIB) echo $((num * 1024)) ;;
  *) error "Cannot parse size string: '$1'" ;;
  esac
}

ram_gib() {
  # Returns total installed RAM in whole GiB (rounded up).
  local kib
  kib="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
  echo $(((kib + 1048575) / 1048576))
}

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

  SINGLE_DISK="$(cfg '.disk' 'disk')"
  [[ -b "$SINGLE_DISK" ]] || error "Disk not found: $SINGLE_DISK"

  # Use blockdev --getsize64 (bytes) for precision — avoids the truncation
  # error from sector-based math on disks that are not exact GiB multiples.
  # Virtual disks from virt-manager are often 1-2 MB short of a round GiB.
  local total_bytes
  total_bytes="$(blockdev --getsize64 "$SINGLE_DISK")"
  local total_mib=$((total_bytes / 1024 / 1024))
  local total_gib=$((total_mib / 1024))
  local ram
  ram="$(ram_gib)"
  info "Disk: $SINGLE_DISK — ${total_mib} MiB (${total_gib} GiB)  |  RAM: ${ram} GiB"

  # ESP size in MiB (parsed from config, default 512M)
  local esp_sz
  esp_sz="$(cfgo '.options.esp_size')"
  esp_sz="${esp_sz:-512M}"
  local esp_mib
  esp_mib="$(parse_size_to_gib "$esp_sz")"
  esp_mib=$((esp_mib * 1024))
  # parse_size_to_gib rounds to whole GiB; handle sub-GiB ESP directly
  case "${esp_sz^^}" in
  *M | *MIB)
    esp_mib="${esp_sz^^}"
    esp_mib="${esp_mib//[^0-9]/}"
    ;;
  *G | *GIB) esp_mib=$((${esp_sz^^//[^0-9]/} * 1024)) ;;
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
    ((swap_gib > swap_cap)) && {
      warn "Swap auto (${swap_gib}G = RAM×2) capped to ${swap_cap}G on this small disk."
      swap_gib=$swap_cap
    }
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
    local pct=$((usable_mib * 70 / 100 / 1024)) # 70% of usable space

    os_gib=$floor
    ((ram_based > os_gib)) && os_gib=$ram_based
    ((pct > os_gib)) && os_gib=$pct

    # Hard cap: never claim more than 85% of usable MiB
    local os_cap_mib=$((usable_mib * 85 / 100))
    local os_cap_gib=$((os_cap_mib / 1024))
    ((os_gib > os_cap_gib && os_cap_gib > 0)) && os_gib=$os_cap_gib

    info "OS size (auto): floor=${floor}G  ram-based=${ram_based}G  70%=$((usable_mib * 70 / 100 / 1024))G  → ${os_gib}G  (cap: ${os_cap_gib}G)"
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
    error "Storage partition would be only ${stor_mib} MiB — too small to be useful.
  Disk usable space: $((usable_mib / 1024)) GiB  |  OS: ${os_gib} GiB
  Fix: use a larger disk, or set a smaller 'os_size' in install.json."
  fi

  if ((os_gib < 15)); then
    error "OS partition (${os_gib} GiB) is too small for Arch Linux + ZFS.
  Minimum recommended: 20 GiB. Use a larger disk."
  fi

  # OS partition size in sectors for sgdisk (uses 512-byte sectors)
  SINGLE_OS_SECTORS=$((os_mib * 1024 * 1024 / 512))

  # ── Layout table ──────────────────────────────────────────────────────────
  echo ""
  echo -e "  ${BOLD}Partition layout — $SINGLE_DISK (${total_mib} MiB):${NC}"
  printf "    %-5s  %-14s  %s\n" "Part" "Size" "Purpose"
  printf "    %-5s  %-14s  %s\n" "----" "--------------" "-------"
  printf "    %-5s  %-14s  %s\n" "p1" "${esp_sz}" "EFI System Partition (FAT32)"
  printf "    %-5s  %-14s  %s\n" "p2" "${os_gib} GiB" "ZFS rpool  —  / /home /var swap(${swap_gib}G)"
  printf "    %-5s  %-14s  %s\n" "p3" "~${stor_gib} GiB" "ZFS dpool  —  /data"
  echo ""
}

# =============================================================================
# PARTITIONING
# =============================================================================

part_name() {
  # Returns the full partition device path for a disk + partition number.
  # NVMe/eMMC use a 'p' separator: nvme0n1 + 1 → nvme0n1p1
  # SATA/SCSI do not:             sda     + 1 → sda1
  local disk="$1" num="$2"
  [[ "$disk" =~ nvme|mmcblk ]] && echo "${disk}p${num}" || echo "${disk}${num}"
}

partition_single_disk() {
  section "Partitioning Single Disk"
  warn "ALL DATA ON $SINGLE_DISK WILL BE DESTROYED."
  confirm "Confirm partitioning?"

  local esp_sz
  esp_sz="$(cfgo '.options.esp_size')"
  esp_sz="${esp_sz:-512M}"

  # Wipe all existing signatures and partition tables
  wipefs -af "$SINGLE_DISK"
  sgdisk --zap-all "$SINGLE_DISK"

  # GPT partition layout:
  #   1  EFI System Partition  (type ef00 = EFI, FAT32)
  #   2  ZFS OS pool           (type bf00 = Solaris/ZFS)
  #   3  ZFS storage pool      (type bf00)
  sgdisk -n1:0:+"${esp_sz}" -t1:ef00 -c1:"EFI System" "$SINGLE_DISK"
  sgdisk -n2:0:+${SINGLE_OS_SECTORS}s -t2:bf00 -c2:"ZFS rpool" "$SINGLE_DISK"
  sgdisk -n3:0:0 -t3:bf00 -c3:"ZFS dpool" "$SINGLE_DISK"

  # Re-probe so the kernel sees the new partition table
  partprobe "$SINGLE_DISK"
  sleep 2

  SINGLE_ESP_PART="$(part_name "$SINGLE_DISK" 1)"
  SINGLE_OS_PART="$(part_name "$SINGLE_DISK" 2)"
  SINGLE_STOR_PART="$(part_name "$SINGLE_DISK" 3)"

  mkfs.fat -F32 -n EFI "$SINGLE_ESP_PART"
  info "Partitioned:"
  info "  ESP     → $SINGLE_ESP_PART"
  info "  rpool   → $SINGLE_OS_PART"
  info "  dpool   → $SINGLE_STOR_PART"
}

# =============================================================================
# ZFS POOL CREATION
# =============================================================================

create_single_pools() {
  section "Creating ZFS Pools (single-disk)"
  build_enc_opts

  local rp
  rp="$(cfgo '.os_pool_name')"
  rp="${rp:-rpool}"
  local dp
  dp="$(cfgo '.storage_pool_name')"
  dp="${dp:-dpool}"
  local ashift
  ashift="$(cfgo '.ashift')"
  ashift="${ashift:-12}"
  local mnt
  mnt="$(cfgo '.storage_mount')"
  mnt="${mnt:-/data}"

  # rpool — single partition, no RAID
  _zpool_create "${rp}" "${ashift}" "${SINGLE_OS_PART}"
  _create_os_datasets "${rp}"

  # dpool — the remaining partition; one dataset at the configured mount
  _zpool_create "${dp}" "${ashift}" "${SINGLE_STOR_PART}"
  zfs create -o mountpoint="${mnt}" "${dp}/storage"
  info "dpool '${dp}' → ${mnt}"
}

# =============================================================================
# ESP MOUNTING
# =============================================================================

mount_single_esp() {
  section "Mounting ESP"
  mkdir -p "${MOUNT_ROOT}/boot/efi"
  mount "$SINGLE_ESP_PART" "${MOUNT_ROOT}/boot/efi"
  info "ESP: $SINGLE_ESP_PART → /boot/efi"
}
