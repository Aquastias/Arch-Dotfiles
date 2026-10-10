#!/usr/bin/env bash
# =============================================================================
# lib/layout/btrfs/multi.sh — btrfs Root Layout Adapter (multi-disk, ADR 0043)
# =============================================================================
# A native multi-disk btrfs raid root (single/raid0/raid1/raid10 over the disks
# in os_pool.disks). Reuses the shared non-ZFS root spine (lib/layout/nonzfs/
# root.sh) for its pure helpers — the per-disk partition planner
# (layout_nonzfs_partition_plan), the swap tail (layout_nonzfs_swap_tail), the plan-field
# reader (layout_plan_field) — and the btrfs subvolume layout + boot emitters
# (btrfs/subvol.sh, btrfs/boot.sh), but OVERRIDES the whole layout seam because a
# raid root spans many disks: each disk gets `ESP + root` (the primary also gets
# a dedicated swap partition), then mkfs.btrfs assembles the raid over every root
# partition. The subvolume layout (@/@home/@log/@pkg/@snapshots) and the
# @-subvol boot (rootflags=subvol=@) are shared with the single-disk adapter; the
# initramfs HOOKS add the `btrfs` scan hook so the raid assembles before mount.
#
# Plaintext only: an encrypted multi-disk btrfs root would need every member's
# LUKS container opened in the initramfs, but the classic `encrypt` hook this
# project commits to opens just one `cryptdevice=`. layout_validate errors on
# encryption — use the single-disk adapter for an encrypted btrfs root.
#
# ESP: every OS disk gets a formatted ESP (mirroring the ZFS multi adapter), but
# only the primary is populated/mounted this pass (boot uses the primary disk).
# =============================================================================

# shellcheck source=../nonzfs/root.sh
source "${BASH_SOURCE[0]%/*}/../nonzfs/root.sh"
# shellcheck source=./boot.sh
source "${BASH_SOURCE[0]%/*}/boot.sh"
# shellcheck source=./subvol.sh
source "${BASH_SOURCE[0]%/*}/subvol.sh"

# INTERNAL STATE (do not reference outside this module):
_LAYOUT_BTRFS_DISKS=()        # OS disks (os_pool.disks), primary first
_LAYOUT_BTRFS_TOPOLOGY=""     # single|raid0|raid1|raid10
_LAYOUT_BTRFS_PLANS=()        # per-disk layout_nonzfs_partition_plan output (parallel)
_LAYOUT_BTRFS_ROOT_PARTS=()   # the btrfs raid member partition per disk
_LAYOUT_BTRFS_ESP_PARTS=()    # the ESP partition per disk

# =============================================================================
# LAYOUT INTERFACE (overrides the single-disk seam sourced from nonzfs/root.sh)
# =============================================================================

layout_validate() {
  layout_enter_phase validate
  layout_validate_esp_size
  [[ "$(install_config_encryption_enabled)" == "true" ]] && error \
    "Encrypted multi-disk btrfs root is unsupported: the classic mkinitcpio" \
    "'encrypt' hook opens only one device. Use a single-disk encrypted btrfs" \
    "root, or a plaintext multi-disk raid."
  mapfile -t _LAYOUT_BTRFS_DISKS \
    < <(jsonc "$CONFIG_FILE" | jq -r '.os_pool.disks[]')
  ((${#_LAYOUT_BTRFS_DISKS[@]} >= 1)) || error "btrfs multi: no os_pool.disks."
  local disk
  for disk in "${_LAYOUT_BTRFS_DISKS[@]}"; do
    layout_disk_exists "$disk" || error "btrfs multi: disk not found: $disk"
  done
  _LAYOUT_BTRFS_TOPOLOGY="$(config_optional '.os_pool.topology')"
  [[ -z "$_LAYOUT_BTRFS_TOPOLOGY" ]] && _LAYOUT_BTRFS_TOPOLOGY=single
  local disk_count="${#_LAYOUT_BTRFS_DISKS[@]}"
  case "$_LAYOUT_BTRFS_TOPOLOGY" in
  single) ;;
  raid0 | raid1) ((disk_count >= 2)) || error \
    "btrfs ${_LAYOUT_BTRFS_TOPOLOGY} root needs ≥2 disks (got ${disk_count})." ;;
  raid10) ((disk_count >= 4 && disk_count % 2 == 0)) || error \
    "btrfs raid10 root needs an even count of ≥4 disks (got ${disk_count})." ;;
  *) error "btrfs root topology '${_LAYOUT_BTRFS_TOPOLOGY}' invalid" \
    "(single/raid0/raid1/raid10)." ;;
  esac
  layout_exit_phase validate
}

# Plan: a per-disk `ESP + [swap] + root` split (the primary alone carries swap),
# reusing the single-disk planner once per disk. Collects the raid member + ESP
# partition for each disk.
_layout_plan_mode() {
  section "Calculating btrfs Multi-Disk Layout (${_LAYOUT_BTRFS_TOPOLOGY})"
  local esp_mib
  esp_mib="$(layout_parse_size_to_mib "$(layout_resolve_esp_size)")"
  _LAYOUT_BTRFS_PLANS=()
  _LAYOUT_BTRFS_ROOT_PARTS=()
  _LAYOUT_BTRFS_ESP_PARTS=()
  local i disk total_mib swap_mib plan root_number
  for i in "${!_LAYOUT_BTRFS_DISKS[@]}"; do
    disk="${_LAYOUT_BTRFS_DISKS[$i]}"
    total_mib=$(( $(blockdev --getsize64 "$disk") / 1024 / 1024 ))
    swap_mib=0
    ((i == 0)) && swap_mib="$(layout_nonzfs_swap_mib "$total_mib")"
    plan="$(layout_nonzfs_partition_plan "$total_mib" "$esp_mib" "$swap_mib")"
    _LAYOUT_BTRFS_PLANS+=("$plan")
    root_number="$(printf '%s\n' "$plan" | layout_plan_field root_part_num)"
    _LAYOUT_BTRFS_ROOT_PARTS+=("$(part_name "$disk" "$root_number")")
    _LAYOUT_BTRFS_ESP_PARTS+=("$(part_name "$disk" 1)")
  done
  info "btrfs ${_LAYOUT_BTRFS_TOPOLOGY} over ${#_LAYOUT_BTRFS_DISKS[@]} disks:" \
       "${_LAYOUT_BTRFS_ROOT_PARTS[*]}"
  # shellcheck disable=SC2034 # consumed by install_state_write / finalize.sh
  LAYOUT_OS_POOL_NAME=""
  # shellcheck disable=SC2034 # consumed by finalize.sh
  LAYOUT_DATA_POOL_NAMES=()
}

# Every OS disk receives an ESP (core resolves LAYOUT_ESP_PARTS from disk p1).
_layout_os_disks() { printf '%s\n' "${_LAYOUT_BTRFS_DISKS[@]}"; }

# A multi-disk btrfs root needs the `btrfs` scan hook so the raid assembles in
# the initramfs before the root mounts (plaintext — no encrypt hook). Under
# impermanence (ADR 0044) the btrfs-rollback hook joins it before `filesystems`.
_layout_publish_boot() {
  local impermanence=""
  [[ "$(install_config_impermanence_enabled)" == "true" ]] && impermanence=impermanence
  # shellcheck disable=SC2034 # consumed by install_state_write
  LAYOUT_HOOKS="$(layout_btrfs_hooks "" multi "$impermanence")"
}

layout_partition() {
  layout_enter_phase partition
  section "Partitioning ${#_LAYOUT_BTRFS_DISKS[@]} Disks" \
          "(btrfs ${_LAYOUT_BTRFS_TOPOLOGY})"
  warn "ALL DATA ON ${_LAYOUT_BTRFS_DISKS[*]} WILL BE DESTROYED."
  confirm "Confirm partitioning?"

  # Each btrfs raid member gets the shared ESP + [swap] + root(8300) GPT ritual
  # (the non-ZFS spine's per-disk helper); btrfs formats one fs over the members.
  local i disk
  for i in "${!_LAYOUT_BTRFS_DISKS[@]}"; do
    disk="${_LAYOUT_BTRFS_DISKS[$i]}"
    layout_nonzfs_partition_one_disk "$disk" "${_LAYOUT_BTRFS_PLANS[$i]}"
  done
  sleep 2

  local index
  for index in "${!_LAYOUT_BTRFS_ESP_PARTS[@]}"; do
    mkfs.fat -F32 -n "EFI$((index + 1))" "${_LAYOUT_BTRFS_ESP_PARTS[$index]}"
  done

  # Swap (primary disk only) → reuse the spine's swap tail via its state vars.
  local primary_swap_number
  primary_swap_number="$(printf '%s\n' "${_LAYOUT_BTRFS_PLANS[0]}" \
    | layout_plan_field swap_part_num)"
  if [[ -n "$primary_swap_number" ]]; then
    _LAYOUT_IMPL_SWAP_PART="$(part_name "${_LAYOUT_BTRFS_DISKS[0]}" "$primary_swap_number")"
    _LAYOUT_IMPL_SWAP_DEV="$_LAYOUT_IMPL_SWAP_PART"
  else
    _LAYOUT_IMPL_SWAP_PART=""; _LAYOUT_IMPL_SWAP_DEV=""
  fi
  info "Partitioned ${#_LAYOUT_BTRFS_DISKS[@]} disks;" \
       "raid members: ${_LAYOUT_BTRFS_ROOT_PARTS[*]}"
  layout_verify_partition_contract
  layout_exit_phase partition
}

layout_create_pools() {
  layout_enter_phase pools
  section "Formatting btrfs ${_LAYOUT_BTRFS_TOPOLOGY} Root + Subvolumes"
  modprobe btrfs 2>/dev/null || true
  # mkfs.btrfs across every member with the chosen profile for data + metadata;
  # a single device / topology=single is a plain single-device mkfs.
  if [[ "$_LAYOUT_BTRFS_TOPOLOGY" == "single" \
        || "${#_LAYOUT_BTRFS_ROOT_PARTS[@]}" -eq 1 ]]; then
    mkfs.btrfs -f "${_LAYOUT_BTRFS_ROOT_PARTS[@]}"
  else
    mkfs.btrfs -f -d "$_LAYOUT_BTRFS_TOPOLOGY" -m "$_LAYOUT_BTRFS_TOPOLOGY" \
      "${_LAYOUT_BTRFS_ROOT_PARTS[@]}"
  fi
  # Register every member so the raid is mountable by any one device.
  btrfs device scan || true

  local root_dev="${_LAYOUT_BTRFS_ROOT_PARTS[0]}"
  layout_btrfs_create_and_mount_subvolumes "$root_dev"

  local uuid source_device
  uuid="$(blkid -s UUID -o value "$root_dev")" # the btrfs fs UUID (all members)
  source_device="UUID=${uuid}"
  # shellcheck disable=SC2034 # consumed by install_state_write
  LAYOUT_ROOT_CMDLINE="$(layout_btrfs_root_cmdline "$uuid" @)"
  layout_nonzfs_swap_tail plain
  # shellcheck disable=SC2034 # consumed by write_fstab
  LAYOUT_FSTAB_EXTRA="$(layout_btrfs_root_fstab "$source_device")${_NZROOT_SWAP_FSTAB}"
  info "btrfs ${_LAYOUT_BTRFS_TOPOLOGY} root + subvolumes mounted at $MOUNT_ROOT"
  layout_exit_phase pools
}

# Mount the primary disk's ESP (secondary ESPs are formatted spares this pass).
layout_mount_esp() {
  layout_enter_phase esp
  section "Mounting ESP"
  mkdir -p "${MOUNT_ROOT}/boot/efi"
  mount "${_LAYOUT_BTRFS_ESP_PARTS[0]}" "${MOUNT_ROOT}/boot/efi"
  info "Primary ESP: ${_LAYOUT_BTRFS_ESP_PARTS[0]} → /boot/efi"
  layout_exit_phase esp
}
