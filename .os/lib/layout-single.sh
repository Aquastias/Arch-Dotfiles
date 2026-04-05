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
        M|MIB) echo $(( (num + 1023) / 1024 )) ;;
        G|GIB) echo "$num" ;;
        T|TIB) echo $(( num * 1024 )) ;;
        *)     error "Cannot parse size string: '$1'" ;;
    esac
}

ram_gib() {
    # Returns total installed RAM in whole GiB (rounded up).
    local kib; kib="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
    echo $(( (kib + 1048575) / 1048576 ))
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

    local total_sectors; total_sectors="$(blockdev --getsz "$SINGLE_DISK")"
    local total_gib=$(( total_sectors * 512 / 1024 / 1024 / 1024 ))
    local ram; ram="$(ram_gib)"
    info "Disk: $SINGLE_DISK — ${total_gib} GiB  |  RAM: ${ram} GiB"

    # ── Swap size ─────────────────────────────────────────────────────────────
    local cfg_swap; cfg_swap="$(cfgo '.options.swap_size')"
    local swap_gib
    if [[ -z "$cfg_swap" || "$cfg_swap" == "auto" ]]; then
        swap_gib=$(( ram * 2 ))
        info "Swap: ${swap_gib} GiB  (RAM × 2, auto)"
    else
        swap_gib="$(parse_size_to_gib "$cfg_swap")"
        info "Swap: ${swap_gib} GiB  (from config)"
    fi

    # ── OS partition size ─────────────────────────────────────────────────────
    local cfg_os; cfg_os="$(cfgo '.os_size')"
    local os_gib
    if [[ -z "$cfg_os" || "$cfg_os" == "auto" ]]; then
        local floor=40
        local ram_based=$(( swap_gib + 30 ))
        local pct=$(( total_gib * 20 / 100 ))
        os_gib=$floor
        (( ram_based > os_gib )) && os_gib=$ram_based
        (( pct       > os_gib )) && os_gib=$pct
        info "OS size (auto): floor=${floor}G  ram-based=${ram_based}G  20%=${pct}G  → ${os_gib}G"
    else
        os_gib="$(parse_size_to_gib "$cfg_os")"
        info "OS size: ${os_gib} GiB  (from config)"
    fi

    # ── Sanity checks ─────────────────────────────────────────────────────────
    local stor_gib=$(( total_gib - os_gib ))
    (( os_gib + 2 < total_gib )) || \
        error "Disk too small. OS needs ${os_gib} GiB but disk is only ${total_gib} GiB."
    (( stor_gib >= 1 )) || \
        error "No space left for storage partition (${stor_gib} GiB remaining). \
Use a larger disk or set a smaller os_size in config."

    # Convert OS size in GiB → sectors (512 bytes each)
    SINGLE_OS_SECTORS=$(( os_gib * 1024 * 1024 * 1024 / 512 ))

    # ── Layout table ──────────────────────────────────────────────────────────
    local esp_sz; esp_sz="$(cfgo '.options.esp_size')"; esp_sz="${esp_sz:-512M}"
    echo ""
    echo -e "  ${BOLD}Partition layout — $SINGLE_DISK (${total_gib} GiB):${NC}"
    printf "    %-5s  %-14s  %s\n" "Part"  "Size"           "Purpose"
    printf "    %-5s  %-14s  %s\n" "----"  "--------------" "-------"
    printf "    %-5s  %-14s  %s\n" "p1"    "${esp_sz}"      "EFI System Partition (FAT32)"
    printf "    %-5s  %-14s  %s\n" "p2"    "${os_gib} GiB"  "ZFS rpool  —  / /home /var swap(${swap_gib}G)"
    printf "    %-5s  %-14s  %s\n" "p3"    "~${stor_gib} GiB" "ZFS dpool  —  /data"
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

    local esp_sz; esp_sz="$(cfgo '.options.esp_size')"; esp_sz="${esp_sz:-512M}"

    # Wipe all existing signatures and partition tables
    wipefs -af "$SINGLE_DISK"
    sgdisk --zap-all "$SINGLE_DISK"

    # GPT partition layout:
    #   1  EFI System Partition  (type ef00 = EFI, FAT32)
    #   2  ZFS OS pool           (type bf00 = Solaris/ZFS)
    #   3  ZFS storage pool      (type bf00)
    sgdisk -n1:0:+"${esp_sz}"             -t1:ef00 -c1:"EFI System"  "$SINGLE_DISK"
    sgdisk -n2:0:+${SINGLE_OS_SECTORS}s   -t2:bf00 -c2:"ZFS rpool"   "$SINGLE_DISK"
    sgdisk -n3:0:0                         -t3:bf00 -c3:"ZFS dpool"   "$SINGLE_DISK"

    # Re-probe so the kernel sees the new partition table
    partprobe "$SINGLE_DISK"
    sleep 2

    SINGLE_ESP_PART="$(part_name "$SINGLE_DISK" 1)"
    SINGLE_OS_PART="$(part_name  "$SINGLE_DISK" 2)"
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

    local rp; rp="$(cfgo '.os_pool_name')"; rp="${rp:-rpool}"
    local dp; dp="$(cfgo '.storage_pool_name')"; dp="${dp:-dpool}"
    local ashift; ashift="$(cfgo '.ashift')"; ashift="${ashift:-12}"
    local mnt; mnt="$(cfgo '.storage_mount')"; mnt="${mnt:-/data}"

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
