#!/usr/bin/env bash
# =============================================================================
# lib/layout/nonzfs/root.sh — shared non-ZFS Root Adapter spine (ADR 0043)
# =============================================================================
# The single-disk Root Layout Adapter body under the ext4/xfs leaves. Lays the
# OS disk out as `ESP + [swap] + root`, optionally LUKS-wraps the root, formats
# it, mounts it at MOUNT_ROOT, and publishes the filesystem-blind boot record
# (LAYOUT_ROOT_CMDLINE / LAYOUT_HOOKS) + the fstab/crypttab tail the FS-agnostic
# bootloader / initcpio / chroot_write_fstab / chroot_write_crypttab consume.
#
# Everything here is filesystem-agnostic except two hooks the per-fs leaf
# (lib/layout/<fs>/single.sh) supplies, mirroring the Data Group Formatter
# pattern (nonzfs/data.sh + <fs>/data.sh's `data_formatter_mkfs`):
#   - root_adapter_mkfs <dev>  → format the root device with the leaf's filesystem.
#   - root_adapter_fstype       → the fstab fs-type column + log label ("ext4"/"xfs").
# The leaf sources this spine, then defines those two functions.
#
# Reuses the shared layout core (lib/layout/core.sh) and the pure non-ZFS cores:
# the partition planner (nonzfs/plan.sh, the slot authority), the device
# resolver (nonzfs/devices.sh), and the shared boot emitters (nonzfs/boot.sh).
#
# Requires (already sourced by 03-install.sh): lib/common.sh (config_required, part_name,
# section/info/warn/confirm), lib/config/install-config.sh, lib/zfs/pools.sh
# (zfs_ram_gib). Provides the seam: layout_validate, _layout_plan_mode,
# _layout_os_disks, _layout_publish_boot, layout_partition, layout_create_pools,
# layout_mount_esp.
#
# INTERNAL STATE (do not reference outside this module):
#   _LAYOUT_IMPL_DISK       — target disk device path
#   _LAYOUT_IMPL_PLAN       — layout_nonzfs_partition_plan output (slots + sizes)
#   _LAYOUT_IMPL_ESP_PART   — ESP partition device
#   _LAYOUT_IMPL_SWAP_PART  — swap partition device ("" when no swap)
#   _LAYOUT_IMPL_ROOT_PART  — root partition device
#   _LAYOUT_IMPL_ROOT_DEV   — root mkfs/mount target (= root part, plaintext)
#   _LAYOUT_IMPL_SWAP_DEV   — swap mkswap target ("" when no swap)
# =============================================================================

# shellcheck source=../core.sh
source "${BASH_SOURCE[0]%/*}/../core.sh"
# shellcheck source=./plan.sh
source "${BASH_SOURCE[0]%/*}/plan.sh"
# shellcheck source=./devices.sh
source "${BASH_SOURCE[0]%/*}/devices.sh"
# shellcheck source=./boot.sh
source "${BASH_SOURCE[0]%/*}/boot.sh"

_LAYOUT_IMPL_DISK=""
_LAYOUT_IMPL_PLAN=""
_LAYOUT_IMPL_ESP_PART=""
_LAYOUT_IMPL_SWAP_PART=""
_LAYOUT_IMPL_ROOT_PART=""
_LAYOUT_IMPL_ROOT_DEV=""
_LAYOUT_IMPL_SWAP_DEV=""
# LUKS container UUID of the root *partition* (encrypted only) — the cmdline's
# cryptdevice=UUID=…; distinct from the root fs UUID inside the mapper.
_LAYOUT_IMPL_LUKS_ROOT_UUID=""

# "encrypted" when the root filesystem is encrypted (LUKS), else "plain". Drives
# device resolution, the boot emitters, and swap handling.
layout_nonzfs_encryption_mode() {
  [[ "$(install_config_encryption_enabled)" == "true" ]] \
    && echo encrypted || echo plain
}

# Resolve the swap *partition* size in MiB (0 = no swap). auto = RAM×2, capped
# at 25% of the disk so the root still fits; an explicit size is honored.
layout_nonzfs_swap_mib() {
  local total_mib="$1"
  [[ "$(install_config_swap_enabled)" == "true" ]] || { echo 0; return; }
  local raw swap_mib cap
  raw="$(config_optional '.options.swap_size')"
  if [[ -z "$raw" || "$raw" == "auto" ]]; then
    swap_mib=$(( $(zfs_ram_gib) * 2 * 1024 ))
    cap=$(( total_mib / 4 ))
    ((swap_mib > cap)) && swap_mib=$cap
  else
    swap_mib=$(( $(layout_parse_size_to_gib "$raw") * 1024 ))
  fi
  echo "$swap_mib"
}

# =============================================================================
# LAYOUT INTERFACE (called by 03-install.sh via the seam)
# =============================================================================

layout_validate() {
  layout_enter_phase validate
  layout_validate_esp_size
  local disk
  disk="$(config_required '.disk' 'disk')"
  layout_disk_exists "$disk" \
    || error "$(root_adapter_fstype) single disk not found: $disk"
  layout_exit_phase validate
}

# Plan hook: compute the partition split via the non-ZFS planner (the slot
# authority) and publish the empty pool record (a non-ZFS root has no pools).
_layout_plan_mode() {
  local fstype; fstype="$(root_adapter_fstype)"
  section "Calculating ${fstype} Single-Disk Layout"
  _LAYOUT_IMPL_DISK="$(config_required '.disk' 'disk')"
  layout_disk_exists "$_LAYOUT_IMPL_DISK" \
    || error "Disk not found: $_LAYOUT_IMPL_DISK"

  local total_bytes total_mib esp_mib swap_mib
  total_bytes="$(blockdev --getsize64 "$_LAYOUT_IMPL_DISK")"
  total_mib=$((total_bytes / 1024 / 1024))
  esp_mib="$(layout_parse_size_to_mib "$(layout_resolve_esp_size)")"
  swap_mib="$(layout_nonzfs_swap_mib "$total_mib")"
  _LAYOUT_IMPL_PLAN="$(layout_nonzfs_partition_plan "$total_mib" "$esp_mib" "$swap_mib")"

  local root_mib
  root_mib="$(printf '%s\n' "$_LAYOUT_IMPL_PLAN" | layout_plan_field root_mib)"
  info "Disk $_LAYOUT_IMPL_DISK: ESP ${esp_mib}M, swap ${swap_mib}M," \
       "root ${root_mib}M (${fstype})"

  # A non-ZFS ROOT has no OS pool; publish the empty OS-pool record the contract
  # expects. Standalone Data Pools, however, are root-fs-agnostic (ADR 0027/0043)
  # — resolve them here so an ext4/xfs root can still host data_pools[].
  # shellcheck disable=SC2034 # consumed by install_state_write / finalize.sh
  LAYOUT_OS_POOL_NAME=""
  # shellcheck disable=SC2034 # consumed by finalize.sh
  LAYOUT_DATA_POOL_NAMES=()
  layout_resolve_data_pools
  # Publish any Standalone Data Pool names to export (finalize's ZFS branch
  # exports the zfs ones cleanly; non-zfs names are tolerated no-op exports).
  local _data_pool_name
  for _data_pool_name in "${_LAYOUT_IMPL_DATA_POOL_NAMES[@]}"; do
    LAYOUT_DATA_POOL_NAMES+=("$_data_pool_name")
  done
}

# The single OS disk that receives the ESP (resolved by core's ESP step).
_layout_os_disks() { printf '%s\n' "$_LAYOUT_IMPL_DISK"; }

# Publish the boot record. HOOKS are knowable now (the `encrypt` hook is added
# for an encrypted root); the root cmdline + fstab tail need the post-mkfs /
# post-LUKS UUID, so they are set in layout_create_pools.
_layout_publish_boot() {
  # shellcheck disable=SC2034 # consumed by install_state_write
  if [[ "$(layout_nonzfs_encryption_mode)" == "encrypted" ]]; then
    LAYOUT_HOOKS="$(layout_nonzfs_hooks encrypted)"
  else
    LAYOUT_HOOKS="$(layout_nonzfs_hooks)"
  fi
}

# LUKS-format + open the root partition with the shared passphrase (collected by
# zfs_collect_encryption_passphrase into ZFS_PASSPHRASE before any disk write — the same
# seam the ZFS path uses). The opened mapper is /dev/mapper/cryptroot, which is
# what layout_nonzfs_root_devices resolved as root_dev.
_nonzfs_root_luks_open() {
  section "Encrypting $(root_adapter_fstype) Root (LUKS)"
  [[ -n "${ZFS_PASSPHRASE:-}" ]] \
    || error "Encrypted root but no passphrase collected (zfs_collect_encryption_passphrase)."
  printf '%s' "$ZFS_PASSPHRASE" \
    | cryptsetup luksFormat --type luks2 --batch-mode "$_LAYOUT_IMPL_ROOT_PART" -
  printf '%s' "$ZFS_PASSPHRASE" \
    | cryptsetup open "$_LAYOUT_IMPL_ROOT_PART" cryptroot -
  _LAYOUT_IMPL_LUKS_ROOT_UUID="$(blkid -s UUID -o value "$_LAYOUT_IMPL_ROOT_PART")"
  info "LUKS root opened → /dev/mapper/cryptroot"
}

# Partition ONE disk as ESP (ef00) + optional swap (8200) + root/member (8300),
# with the part numbers + sizes the non-ZFS planner emitted (layout_nonzfs_partition_plan).
# The shared per-disk GPT ritual for the single ext4/xfs root spine AND the btrfs
# multi adapter (one call per raid member) — formerly two byte-identical copies.
# Wipes + zaps first; partprobes after. The caller mkfs.fat's the ESP.
layout_nonzfs_partition_one_disk() {
  local disk="$1" plan="$2"
  local esp_number swap_number root_number esp_mib swap_mib
  esp_number="$(printf '%s\n' "$plan" | layout_plan_field esp_part_num)"
  swap_number="$(printf '%s\n' "$plan" | layout_plan_field swap_part_num)"
  root_number="$(printf '%s\n' "$plan" | layout_plan_field root_part_num)"
  esp_mib="$(printf '%s\n' "$plan" | layout_plan_field esp_mib)"
  swap_mib="$(printf '%s\n' "$plan" | layout_plan_field swap_mib)"

  wipefs -af "$disk"
  sgdisk --zap-all "$disk"
  # GPT: ESP (ef00) + optional Linux swap (8200) + Linux filesystem (8300, rest).
  sgdisk -n"${esp_number}":0:+"${esp_mib}"M -t"${esp_number}":ef00 \
    -c"${esp_number}":"EFI System" "$disk"
  if [[ -n "$swap_number" ]]; then
    sgdisk -n"${swap_number}":0:+"${swap_mib}"M -t"${swap_number}":8200 \
      -c"${swap_number}":"swap" "$disk"
  fi
  sgdisk -n"${root_number}":0:0 -t"${root_number}":8300 -c"${root_number}":"root" "$disk"
  partprobe "$disk"
}

layout_partition() {
  layout_enter_phase partition
  section "Partitioning Single Disk ($(root_adapter_fstype))"
  warn "ALL DATA ON $_LAYOUT_IMPL_DISK WILL BE DESTROYED."
  confirm "Confirm partitioning?"

  layout_nonzfs_partition_one_disk "$_LAYOUT_IMPL_DISK" "$_LAYOUT_IMPL_PLAN"
  layout_settle

  # Resolve the device paths from the plan. Encrypted → root_dev/swap_dev are the
  # /dev/mapper/crypt* the resolver names; plaintext → the bare partitions.
  local encryption devs
  encryption="$(layout_nonzfs_encryption_mode)"
  devs="$(layout_nonzfs_root_devices "$_LAYOUT_IMPL_DISK" "$_LAYOUT_IMPL_PLAN" "$encryption")"
  _LAYOUT_IMPL_ESP_PART="$(printf '%s\n' "$devs" | layout_plan_field esp_part)"
  _LAYOUT_IMPL_SWAP_PART="$(layout_plan_field swap_part <<<"$devs")"
  _LAYOUT_IMPL_ROOT_PART="$(layout_plan_field root_part <<<"$devs")"
  _LAYOUT_IMPL_ROOT_DEV="$(printf '%s\n' "$devs" | layout_plan_field root_dev)"
  _LAYOUT_IMPL_SWAP_DEV="$(printf '%s\n' "$devs" | layout_plan_field swap_dev)"

  mkfs.fat -F32 -n EFI "$_LAYOUT_IMPL_ESP_PART"
  # Open the root LUKS container so root_dev (/dev/mapper/cryptroot) exists for
  # mkfs. Swap stays raw — crypttab random-keys it at boot (see create verb).
  [[ "$encryption" == "encrypted" ]] && _nonzfs_root_luks_open
  info "Partitioned: ESP $_LAYOUT_IMPL_ESP_PART," \
       "root $_LAYOUT_IMPL_ROOT_DEV${_LAYOUT_IMPL_SWAP_DEV:+, swap $_LAYOUT_IMPL_SWAP_DEV}"
  # Standalone Data Pool disks (root-fs-agnostic, ADR 0027/0043).
  layout_partition_data_pools
  layout_verify_partition_contract
  layout_exit_phase partition
}

# Resolve the swap fstab tail + crypttab for the already-resolved swap device.
# Sets two globals (NOT returned via $() — command substitution would trap them
# in a subshell): _NZROOT_SWAP_FSTAB (the `\n\n# swap…` tail, "" when no swap)
# and LAYOUT_CRYPTTAB (the cryptswap line, "" unless encrypted swap). Shared by
# the ext4/xfs spine and the btrfs override. Disk-touching (mkswap/blkid).
# Encrypted swap is a random-key dm-crypt re-keyed each boot (hibernate out of
# scope); the raw partition stays unformatted (crypttab's `swap` option formats
# it at boot, PARTUUID stable across re-key). Plaintext swap is mkswap'd + by-UUID.
layout_nonzfs_swap_tail() {
  local encryption="$1"
  _NZROOT_SWAP_FSTAB=""
  # shellcheck disable=SC2034 # consumed by chroot_write_crypttab (chroot.sh)
  LAYOUT_CRYPTTAB=""
  if [[ "$encryption" == "encrypted" ]]; then
    [[ -n "$_LAYOUT_IMPL_SWAP_PART" ]] || return 0
    local swap_partuuid
    swap_partuuid="$(blkid -s PARTUUID -o value "$_LAYOUT_IMPL_SWAP_PART")"
    LAYOUT_CRYPTTAB="cryptswap  PARTUUID=${swap_partuuid}  /dev/urandom"
    LAYOUT_CRYPTTAB+="  swap,cipher=aes-xts-plain64,size=256"
    _NZROOT_SWAP_FSTAB=$'\n\n'"# swap (encrypted, random key)"
    _NZROOT_SWAP_FSTAB+=$'\n'"/dev/mapper/cryptswap  none  swap  defaults  0 0"
  else
    [[ -n "$_LAYOUT_IMPL_SWAP_DEV" ]] || return 0
    mkswap "$_LAYOUT_IMPL_SWAP_DEV"
    local swap_uuid
    swap_uuid="$(blkid -s UUID -o value "$_LAYOUT_IMPL_SWAP_DEV")"
    _NZROOT_SWAP_FSTAB=$'\n\n'"# swap"$'\n'"UUID=${swap_uuid}  none  swap  defaults  0 0"
  fi
}

# The "create" seam verb: format the root with the leaf's mkfs, make swap, mount
# the root at MOUNT_ROOT (so pacstrap installs into it), and — now the UUIDs
# exist — publish the root cmdline + the fstab root/swap lines.
layout_create_pools() {
  layout_enter_phase pools
  local fstype; fstype="$(root_adapter_fstype)"
  section "Formatting ${fstype} Root"
  root_adapter_mkfs "$_LAYOUT_IMPL_ROOT_DEV"
  # The live ISO ships the mkfs tools but may not have the fs kernel module
  # loaded, so the freshly-formatted root can't be mounted here without it (ext4
  # is built-in; xfs/btrfs are modules). Load it; harmless if built-in/loaded.
  modprobe "$fstype" 2>/dev/null || true
  mount "$_LAYOUT_IMPL_ROOT_DEV" "$MOUNT_ROOT"

  local encryption extra
  encryption="$(layout_nonzfs_encryption_mode)"
  if [[ "$encryption" == "encrypted" ]]; then
    # Boot by the LUKS container UUID; the root fs lives inside the mapper, so
    # fstab references the mapper (the encrypt hook opens it before mount).
    # shellcheck disable=SC2034 # consumed by install_state_write
    LAYOUT_ROOT_CMDLINE="$(layout_nonzfs_root_cmdline "$_LAYOUT_IMPL_LUKS_ROOT_UUID" encrypted)"
    extra="# root"$'\n'"/dev/mapper/cryptroot  /  ${fstype}  rw,relatime  0 1"
  else
    local root_uuid
    root_uuid="$(blkid -s UUID -o value "$_LAYOUT_IMPL_ROOT_DEV")"
    # shellcheck disable=SC2034 # consumed by install_state_write
    LAYOUT_ROOT_CMDLINE="$(layout_nonzfs_root_cmdline "$root_uuid")"
    extra="# root"$'\n'"UUID=${root_uuid}  /  ${fstype}  rw,relatime  0 1"
  fi
  # Append the swap fstab tail + set LAYOUT_CRYPTTAB (shared with the btrfs
  # override; sets globals so command substitution can't trap them in a subshell).
  layout_nonzfs_swap_tail "$encryption"
  extra+="$_NZROOT_SWAP_FSTAB"
  # shellcheck disable=SC2034 # consumed by chroot_write_fstab
  LAYOUT_FSTAB_EXTRA="$extra"
  info "${fstype} root formatted + mounted at $MOUNT_ROOT"
  # Standalone Data Pools — each formatted by its own Data Group Formatter leaf
  # (zfs/ext4/xfs/btrfs) via the shared seam; a non-ZFS root can host any of them.
  layout_create_data_pools
  layout_exit_phase pools
}

layout_mount_esp() {
  layout_enter_phase esp
  section "Mounting ESP"
  mkdir -p "${MOUNT_ROOT}/boot/efi"
  mount "$_LAYOUT_IMPL_ESP_PART" "${MOUNT_ROOT}/boot/efi"
  info "ESP: $_LAYOUT_IMPL_ESP_PART → /boot/efi"
  layout_exit_phase esp
}
