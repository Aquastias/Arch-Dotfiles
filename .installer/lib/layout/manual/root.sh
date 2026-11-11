#!/usr/bin/env bash
# =============================================================================
# lib/layout/manual/root.sh — Manual Partitioning Root Layout Adapter (ADR 0073)
# =============================================================================
# The escape-hatch adapter, selected when disk_config.kind is `manual`. Unlike
# every pool/skeleton adapter it does NOT wipe or repartition — the operator's
# cfdisk table is authoritative. It consumes their partitions[] assignment via
# the pure planner (manual/plan.sh), formats only the partitions marked
# `format`, mounts them under MOUNT_ROOT (root first, then deeper paths, ESP
# last), activates any [swap] partition, and publishes the plain (non-ZFS,
# non-LUKS) boot record the FS-agnostic bootloader / initcpio /
# chroot_write_fstab consume. There is no encryption, impermanence, or
# data-pool path here (they are disabled the moment Manual Partitioning is
# toggled on).
#
# Provides the layout seam 03-install.sh drives: layout_validate, layout_plan,
# layout_partition, layout_create_pools, layout_mount_esp. Reuses the shared
# layout core (phases + plan-field reader + the ESP contract) and the non-ZFS
# boot emitters (a manual root is exactly a plain non-ZFS root by UUID).
#
# INTERNAL STATE (do not reference outside this module):
#   _MANUAL_PLAN         — layout_manual_partition_plan output (records +
#                          summary)
#   _MANUAL_ESP_DEV      — the ESP partition device (mounted at /boot/efi)
#   _MANUAL_ROOT_DEV     — the root partition device (mounted at MOUNT_ROOT)
#   _MANUAL_ESP_FORMAT   — "true" to mkfs the ESP, "false" to keep it (dualboot)
# =============================================================================

# shellcheck source=../core.sh
source "${BASH_SOURCE[0]%/*}/../core.sh"
# shellcheck source=./plan.sh
source "${BASH_SOURCE[0]%/*}/plan.sh"
# shellcheck source=../nonzfs/boot.sh
source "${BASH_SOURCE[0]%/*}/../nonzfs/boot.sh"

_MANUAL_PLAN=""
_MANUAL_ESP_DEV=""
_MANUAL_ROOT_DEV=""
_MANUAL_ESP_FORMAT=""

# mkfs one partition with the operator's chosen filesystem. -F/-f: don't prompt
# over an existing signature (the operator asked to format it).
layout_manual_mkfs() {
  local filesystem="$1" dev="$2"
  case "$filesystem" in
  ext4)  mkfs.ext4  -F "$dev" ;;
  xfs)   mkfs.xfs   -f "$dev" ;;
  btrfs) mkfs.btrfs -f "$dev" ;;
  fat32) mkfs.fat -F32 "$dev" ;;
  *) error "Manual layout: unknown filesystem '${filesystem}' for ${dev}." ;;
  esac
}

# =============================================================================
# LAYOUT INTERFACE (called by 03-install.sh via the seam)
# =============================================================================

# Validate the operator's assignment before any disk write, by running the pure
# planner purely for its side effect (it aborts on a missing/duplicate root or a
# missing/non-FAT32 ESP).
layout_validate() {
  layout_enter_phase validate
  layout_manual_partition_plan "$(install_config_partitions_json)" >/dev/null
  layout_exit_phase validate
}

# _manual_root_esp_format <plan> — the format flag (true/false) of the plan's
# /boot/efi mount record.
_manual_root_esp_format() {
  local tag _device mountpoint _filesystem format
  while IFS=$'\t' read -r tag _device mountpoint _filesystem format; do
    if [[ "$tag" == mount && "$mountpoint" == /boot/efi ]]; then
      printf '%s\n' "$format"
    fi
  done < <(printf '%s\n' "$1")
}

# Plan: resolve the assignment into the LAYOUT_* record. No disk writes. The
# root cmdline + fstab tail need post-mkfs UUIDs, so they are set in the create
# verb; the hooks + ESP + empty pool record are knowable now.
layout_plan() {
  layout_enter_phase plan
  section "Manual Partitioning Layout"
  _MANUAL_PLAN="$(layout_manual_partition_plan \
    "$(install_config_partitions_json)")"
  _MANUAL_ESP_DEV="$(layout_plan_field esp_device "$_MANUAL_PLAN")"
  _MANUAL_ROOT_DEV="$(layout_plan_field root_device "$_MANUAL_PLAN")"
  _MANUAL_ESP_FORMAT="$(_manual_root_esp_format "$_MANUAL_PLAN")"

  # A manual root has no OS pool and no data pools.
  # shellcheck disable=SC2034 # consumed by install_state_write / finalize.sh
  LAYOUT_OS_POOL_NAME=""
  # shellcheck disable=SC2034 # consumed by finalize.sh
  LAYOUT_DATA_POOL_NAMES=()
  # The operator-chosen ESP partition (not derived as p1 of a disk).
  # shellcheck disable=SC2034 # consumed by chroot.sh / finalize.sh
  LAYOUT_ESP_PARTS=("$_MANUAL_ESP_DEV")
  # Plain non-ZFS HOOKS (no zfs, no encrypt).
  # shellcheck disable=SC2034 # consumed by install_state_write
  LAYOUT_HOOKS="$(layout_nonzfs_hooks)"

  info "Manual layout: root $_MANUAL_ROOT_DEV, ESP $_MANUAL_ESP_DEV"
  _layout_verify_plan_contract
  layout_exit_phase plan
}

# Partition: a no-op. The operator's cfdisk table already exists; we neither
# wipe nor repartition. Settle the kernel's device view so the assigned
# partitions are present before we format/mount them.
layout_partition() {
  layout_enter_phase partition
  section "Manual Partitioning (using the operator's table)"
  udevadm settle 2>/dev/null || true
  layout_verify_partition_contract
  layout_exit_phase partition
}

# Create: format the marked partitions and mount the tree. Named for the seam
# verb (there are no pools here). Mounts in plan order — root first, then deeper
# paths — so parents mount before children; the ESP is left to layout_mount_esp.
layout_create_pools() {
  layout_enter_phase pools
  section "Formatting & mounting the manual layout"

  local extra="" tag dev mountpoint filesystem format uuid mount_options fsck
  while IFS=$'\t' read -r tag dev mountpoint filesystem format; do
    [[ "$tag" == "mount" ]] || continue
    # The ESP is mounted by layout_mount_esp.
    [[ "$mountpoint" == "/boot/efi" ]] && continue
    if [[ "$format" == "true" ]]; then
      layout_manual_mkfs "$filesystem" "$dev"
      # The live ISO may ship the mkfs tool without the fs module loaded.
      modprobe "$filesystem" 2>/dev/null || true
    fi
    if [[ "$mountpoint" == "/" ]]; then
      mount "$dev" "$MOUNT_ROOT"
      mount_options="rw,relatime"; fsck=1
    else
      mkdir -p "${MOUNT_ROOT}${mountpoint}"
      mount "$dev" "${MOUNT_ROOT}${mountpoint}"
      mount_options="defaults"; fsck=2
    fi
    uuid="$(blkid -s UUID -o value "$dev")"
    extra+="# ${mountpoint}"$'\n'
    extra+="UUID=${uuid}  ${mountpoint}  ${filesystem}  ${mount_options}"
    extra+="  0 ${fsck}"$'\n'
    info "  ${dev} → ${mountpoint}" \
      "(${filesystem}$([[ "$format" == true ]] && echo ' fmt'))"
  done < <(printf '%s\n' "$_MANUAL_PLAN")

  # Boot by the root filesystem's UUID (stable across device reshuffles).
  local root_uuid; root_uuid="$(blkid -s UUID -o value "$_MANUAL_ROOT_DEV")"
  # shellcheck disable=SC2034 # consumed by install_state_write
  LAYOUT_ROOT_CMDLINE="$(layout_nonzfs_root_cmdline "$root_uuid")"

  # The operator's [swap] partitions, on and in the fstab ($(…) drops the
  # last newline, so it goes back).
  local swap_lines
  swap_lines="$(_manual_root_activate_swap)"
  [[ -n "$swap_lines" ]] && extra+="$swap_lines"$'\n'

  # shellcheck disable=SC2034 # consumed by chroot_write_fstab
  LAYOUT_FSTAB_EXTRA="$extra"
  # No LUKS on the manual path.
  # shellcheck disable=SC2034 # consumed by chroot_write_crypttab
  LAYOUT_CRYPTTAB=""
  layout_exit_phase pools
}

# _manual_root_activate_swap — mkswap + swapon each partition the operator
# cut (type 8200) and assigned [swap]; prints their fstab lines, each with
# its newline (progress goes to stderr).
_manual_root_activate_swap() {
  local tag dev swap_uuid
  while IFS=$'\t' read -r tag dev; do
    [[ "$tag" == "swap" ]] || continue
    mkswap "$dev" >&2
    swapon "$dev" 2>/dev/null || true
    swap_uuid="$(blkid -s UUID -o value "$dev")"
    printf '# swap\nUUID=%s  none  swap  defaults  0 0\n' "$swap_uuid"
    info "  ${dev} → swap" >&2
  done < <(printf '%s\n' "$_MANUAL_PLAN")
}

# Mount the ESP. Format it only when the operator marked it (a kept ESP is a
# shared/dual-boot partition we must not wipe). chroot_write_fstab writes
# its fstab line from LAYOUT_ESP_PARTS.
layout_mount_esp() {
  layout_enter_phase esp
  section "Mounting ESP"
  [[ "$_MANUAL_ESP_FORMAT" == "true" ]] \
    && mkfs.fat -F32 -n EFI "$_MANUAL_ESP_DEV"
  mkdir -p "${MOUNT_ROOT}/boot/efi"
  # Load vfat and name the type: the live ISO may not have the module loaded,
  # and auto-probing then fails (VM case: "Can't find a SQUASHFS superblock").
  modprobe vfat 2>/dev/null || true
  udevadm settle 2>/dev/null || true
  mount -t vfat "$_MANUAL_ESP_DEV" "${MOUNT_ROOT}/boot/efi"
  info "ESP: $_MANUAL_ESP_DEV → /boot/efi"
  layout_exit_phase esp
}
