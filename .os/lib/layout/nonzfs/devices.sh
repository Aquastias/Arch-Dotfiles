#!/usr/bin/env bash
# =============================================================================
# lib/layout/nonzfs/devices.sh — non-ZFS root device resolver (ADR 0043)
# =============================================================================
# The pure mapping core under the ext4/xfs/btrfs Root Adapters. The non-ZFS
# partition planner (plan.sh) decides the partition *sizes*; this module decides
# the partition *devices* for the `ESP + [swap] + root` layout and resolves the
# boot/mkfs targets, applying the LUKS mapper when the root is encrypted:
#   - plaintext → the root/swap devices are the bare partitions.
#   - encrypted → the root is opened as /dev/mapper/cryptroot and swap as
#     /dev/mapper/cryptswap; `luks_containers` lists `<part>:<mapper>` pairs the
#     adapter feeds to `cryptsetup luksFormat`/`luksOpen`.
#
# Partition numbering is NOT decided here — the resolver reads the slots the
# planner emits (esp_part_num/swap_part_num/root_part_num) so the planner stays
# the single authority and the two can't drift on "which partition is root".
#
# Pure: partition paths come from part_name (available at call time, like
# plan.sh's use of error()); no disk access.
#
# Public API:
#   nonzfs_root_devices <disk> <plan> <plain|encrypted>
#     <plan> is the key=value text from nonzfs_partition_plan.
#     → emits a `key=value` plan on stdout: esp_part, swap_part (empty when no
#       swap), root_part, root_dev, swap_dev (empty when no swap), and
#       luks_containers (space-separated `<part>:<mapper>`, empty when plain).
# =============================================================================

# Pull a single key=value field out of the planner's emitted plan text.
_nonzfs_plan_field() { grep -E "^$1=" | cut -d= -f2-; }

nonzfs_root_devices() {
  local disk="$1" plan="$2" enc="$3"

  local esp_num swap_num root_num
  esp_num="$(_nonzfs_plan_field esp_part_num   <<<"$plan")"
  swap_num="$(_nonzfs_plan_field swap_part_num <<<"$plan")"
  root_num="$(_nonzfs_plan_field root_part_num <<<"$plan")"

  local esp_part swap_part root_part
  esp_part="$(part_name "$disk" "$esp_num")"
  root_part="$(part_name "$disk" "$root_num")"
  swap_part=""
  [[ -n "$swap_num" ]] && swap_part="$(part_name "$disk" "$swap_num")"

  local root_dev="$root_part" swap_dev="$swap_part" luks_containers=""
  if [[ "$enc" == "encrypted" ]]; then
    root_dev="/dev/mapper/cryptroot"
    luks_containers="${root_part}:cryptroot"
    if [[ -n "$swap_part" ]]; then
      swap_dev="/dev/mapper/cryptswap"
      luks_containers+=" ${swap_part}:cryptswap"
    fi
  fi

  printf 'esp_part=%s\n'        "$esp_part"
  printf 'swap_part=%s\n'       "$swap_part"
  printf 'root_part=%s\n'       "$root_part"
  printf 'root_dev=%s\n'        "$root_dev"
  printf 'swap_dev=%s\n'        "$swap_dev"
  printf 'luks_containers=%s\n' "$luks_containers"
}
