#!/usr/bin/env bash
# =============================================================================
# lib/layout/ext4/single.sh — ext4 Root Layout Adapter (single-disk, ADR 0043)
# =============================================================================
# The first non-ZFS Root Layout Adapter. Lays the OS disk out as
# `ESP + [swap] + root`, formats the root ext4, and publishes the
# filesystem-blind boot record (LAYOUT_ROOT_CMDLINE / LAYOUT_HOOKS) +
# fstab tail the FS-agnostic bootloader / initcpio / write_fstab consume.
#
# Reuses the shared spine (lib/layout/core.sh) and the pure non-ZFS cores: the
# partition planner (nonzfs/plan.sh, the slot authority), the device resolver
# (nonzfs/devices.sh), and the ext4 boot emitters (ext4/boot.sh). Encryption
# (LUKS) layers on in a later slice; this adapter is plaintext.
#
# Requires (already sourced by 03-install.sh): lib/common.sh (cfg, part_name,
# section/info/warn/confirm), lib/config/accessors.sh, lib/zfs/pools.sh
# (ram_gib). Provides the seam: layout_validate, _layout_plan_mode,
# _layout_os_disks, _layout_publish_boot, layout_partition, layout_create_pools,
# layout_mount_esp.
#
# INTERNAL STATE (do not reference outside this module):
#   _LAYOUT_IMPL_DISK       — target disk device path
#   _LAYOUT_IMPL_PLAN       — nonzfs_partition_plan output (slots + sizes)
#   _LAYOUT_IMPL_ESP_PART   — ESP partition device
#   _LAYOUT_IMPL_SWAP_PART  — swap partition device ("" when no swap)
#   _LAYOUT_IMPL_ROOT_PART  — root partition device
#   _LAYOUT_IMPL_ROOT_DEV   — root mkfs/mount target (= root part, plaintext)
#   _LAYOUT_IMPL_SWAP_DEV   — swap mkswap target ("" when no swap)
# =============================================================================

# shellcheck source=../core.sh
source "${BASH_SOURCE[0]%/*}/../core.sh"
# shellcheck source=../nonzfs/plan.sh
source "${BASH_SOURCE[0]%/*}/../nonzfs/plan.sh"
# shellcheck source=../nonzfs/devices.sh
source "${BASH_SOURCE[0]%/*}/../nonzfs/devices.sh"
# shellcheck source=./boot.sh
source "${BASH_SOURCE[0]%/*}/boot.sh"

_LAYOUT_IMPL_DISK=""
_LAYOUT_IMPL_PLAN=""
_LAYOUT_IMPL_ESP_PART=""
_LAYOUT_IMPL_SWAP_PART=""
_LAYOUT_IMPL_ROOT_PART=""
_LAYOUT_IMPL_ROOT_DEV=""
_LAYOUT_IMPL_SWAP_DEV=""

# Read one key=value field from a `key=value` plan/device text on stdin.
_ext4_field() { grep -E "^$1=" | cut -d= -f2-; }

# Resolve the swap *partition* size in MiB (0 = no swap). auto = RAM×2, capped
# at 25% of the disk so the root still fits; an explicit size is honored.
_ext4_swap_mib() {
  local total_mib="$1"
  [[ "$(install_config_swap_enabled)" == "true" ]] || { echo 0; return; }
  local raw swap_mib cap
  raw="$(cfgo '.options.swap_size')"
  if [[ -z "$raw" || "$raw" == "auto" ]]; then
    swap_mib=$(( $(ram_gib) * 2 * 1024 ))
    cap=$(( total_mib / 4 ))
    ((swap_mib > cap)) && swap_mib=$cap
  else
    swap_mib=$(( $(parse_size_to_gib "$raw") * 1024 ))
  fi
  echo "$swap_mib"
}

# =============================================================================
# LAYOUT INTERFACE (called by 03-install.sh via the seam)
# =============================================================================

layout_validate() {
  _layout_enter_phase validate
  layout_validate_esp_size
  local d
  d="$(cfg '.disk' 'disk')"
  [[ -b "$d" ]] || error "ext4 single disk not found: $d"
  _layout_exit_phase validate
}

# Plan hook: compute the partition split via the non-ZFS planner (the slot
# authority) and publish the empty pool record (ext4 has no pools).
_layout_plan_mode() {
  section "Calculating ext4 Single-Disk Layout"
  _LAYOUT_IMPL_DISK="$(cfg '.disk' 'disk')"
  [[ -b "$_LAYOUT_IMPL_DISK" ]] || error "Disk not found: $_LAYOUT_IMPL_DISK"

  local total_bytes total_mib esp_mib swap_mib
  total_bytes="$(blockdev --getsize64 "$_LAYOUT_IMPL_DISK")"
  total_mib=$((total_bytes / 1024 / 1024))
  esp_mib="$(parse_size_to_mib "$(layout_resolve_esp_size)")"
  swap_mib="$(_ext4_swap_mib "$total_mib")"
  _LAYOUT_IMPL_PLAN="$(nonzfs_partition_plan "$total_mib" "$esp_mib" "$swap_mib")"

  local root_mib
  root_mib="$(printf '%s\n' "$_LAYOUT_IMPL_PLAN" | _ext4_field root_mib)"
  info "Disk $_LAYOUT_IMPL_DISK: ESP ${esp_mib}M, swap ${swap_mib}M," \
       "root ${root_mib}M (ext4)"

  # ext4 has no pools; publish the empty record the contract/state expect.
  # shellcheck disable=SC2034 # consumed by install_state_write / finalize.sh
  LAYOUT_OS_POOL_NAME=""
  # shellcheck disable=SC2034 # consumed by finalize.sh
  LAYOUT_DATA_POOL_NAMES=()
}

# The single OS disk that receives the ESP (resolved by core's ESP step).
_layout_os_disks() { printf '%s\n' "$_LAYOUT_IMPL_DISK"; }

# Publish the boot record. HOOKS are knowable now; the root cmdline + fstab tail
# need the post-mkfs UUID, so they are set in layout_create_pools.
_layout_publish_boot() {
  # shellcheck disable=SC2034 # consumed by install_state_write
  LAYOUT_HOOKS="$(ext4_hooks)"
}

layout_partition() {
  _layout_enter_phase partition
  section "Partitioning Single Disk (ext4)"
  warn "ALL DATA ON $_LAYOUT_IMPL_DISK WILL BE DESTROYED."
  confirm "Confirm partitioning?"

  local esp_num swap_num root_num esp_mib swap_mib
  esp_num="$(printf '%s\n' "$_LAYOUT_IMPL_PLAN" | _ext4_field esp_part_num)"
  swap_num="$(printf '%s\n' "$_LAYOUT_IMPL_PLAN" | _ext4_field swap_part_num)"
  root_num="$(printf '%s\n' "$_LAYOUT_IMPL_PLAN" | _ext4_field root_part_num)"
  esp_mib="$(printf '%s\n' "$_LAYOUT_IMPL_PLAN" | _ext4_field esp_mib)"
  swap_mib="$(printf '%s\n' "$_LAYOUT_IMPL_PLAN" | _ext4_field swap_mib)"

  wipefs -af "$_LAYOUT_IMPL_DISK"
  sgdisk --zap-all "$_LAYOUT_IMPL_DISK"
  # GPT: ESP (ef00) + optional Linux swap (8200) + Linux filesystem (8300, rest).
  sgdisk -n"${esp_num}":0:+"${esp_mib}"M -t"${esp_num}":ef00 \
    -c"${esp_num}":"EFI System" "$_LAYOUT_IMPL_DISK"
  if [[ -n "$swap_num" ]]; then
    sgdisk -n"${swap_num}":0:+"${swap_mib}"M -t"${swap_num}":8200 \
      -c"${swap_num}":"swap" "$_LAYOUT_IMPL_DISK"
  fi
  sgdisk -n"${root_num}":0:0 -t"${root_num}":8300 \
    -c"${root_num}":"root" "$_LAYOUT_IMPL_DISK"
  partprobe "$_LAYOUT_IMPL_DISK"
  sleep 2

  # Resolve the device paths from the plan (plaintext: bare partitions).
  local devs
  devs="$(nonzfs_root_devices "$_LAYOUT_IMPL_DISK" "$_LAYOUT_IMPL_PLAN" plain)"
  _LAYOUT_IMPL_ESP_PART="$(printf '%s\n' "$devs" | _ext4_field esp_part)"
  _LAYOUT_IMPL_SWAP_PART="$(printf '%s\n' "$devs" | _ext4_field swap_part)"
  _LAYOUT_IMPL_ROOT_PART="$(printf '%s\n' "$devs" | _ext4_field root_part)"
  _LAYOUT_IMPL_ROOT_DEV="$(printf '%s\n' "$devs" | _ext4_field root_dev)"
  _LAYOUT_IMPL_SWAP_DEV="$(printf '%s\n' "$devs" | _ext4_field swap_dev)"

  mkfs.fat -F32 -n EFI "$_LAYOUT_IMPL_ESP_PART"
  info "Partitioned: ESP $_LAYOUT_IMPL_ESP_PART," \
       "root $_LAYOUT_IMPL_ROOT_DEV${_LAYOUT_IMPL_SWAP_DEV:+, swap $_LAYOUT_IMPL_SWAP_DEV}"
  _layout_verify_partition_contract
  _layout_exit_phase partition
}

# The "create" seam verb: for ext4 it formats the root, makes swap, mounts the
# root at MOUNT_ROOT (so pacstrap installs into it), and — now the UUIDs exist —
# publishes the root cmdline + the fstab root/swap lines.
layout_create_pools() {
  _layout_enter_phase pools
  section "Formatting ext4 Root"
  mkfs.ext4 -F "$_LAYOUT_IMPL_ROOT_DEV"
  mount "$_LAYOUT_IMPL_ROOT_DEV" "$MOUNT_ROOT"

  local root_uuid extra
  root_uuid="$(blkid -s UUID -o value "$_LAYOUT_IMPL_ROOT_DEV")"
  # shellcheck disable=SC2034 # consumed by install_state_write
  LAYOUT_ROOT_CMDLINE="$(ext4_root_cmdline "$root_uuid")"
  extra="# root"$'\n'"UUID=${root_uuid}  /  ext4  rw,relatime  0 1"

  if [[ -n "$_LAYOUT_IMPL_SWAP_DEV" ]]; then
    mkswap "$_LAYOUT_IMPL_SWAP_DEV"
    local swap_uuid
    swap_uuid="$(blkid -s UUID -o value "$_LAYOUT_IMPL_SWAP_DEV")"
    extra+=$'\n\n'"# swap"$'\n'"UUID=${swap_uuid}  none  swap  defaults  0 0"
  fi
  # shellcheck disable=SC2034 # consumed by write_fstab
  LAYOUT_FSTAB_EXTRA="$extra"
  info "ext4 root formatted + mounted at $MOUNT_ROOT"
  _layout_exit_phase pools
}

layout_mount_esp() {
  _layout_enter_phase esp
  section "Mounting ESP"
  mkdir -p "${MOUNT_ROOT}/boot/efi"
  mount "$_LAYOUT_IMPL_ESP_PART" "${MOUNT_ROOT}/boot/efi"
  info "ESP: $_LAYOUT_IMPL_ESP_PART → /boot/efi"
  _layout_exit_phase esp
}
