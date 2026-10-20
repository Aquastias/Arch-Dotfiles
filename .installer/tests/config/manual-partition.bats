#!/usr/bin/env bats
# Tests for the Manual Partitioning assignment model (ADR 0073): seeding the
# assignment table from a disk's partition list (lsblk JSON), pre-filling the
# ESP and swap from partition type, editing an entry, and the Proceed-only
# terminal-action guard. Pure: JSON in, JSON out, no disk access. The cfdisk
# launch + live lsblk re-read are VM-verified (the manual matrix case).

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/config/config-state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/manual-partition.sh"
}

# A canonical `lsblk -J -b -o PATH,TYPE,FSTYPE,PARTTYPE,PARTTYPENAME` payload:
# a fresh ESP, a blank root, an existing (kept) /home, and a swap partition.
LSBLK='{"blockdevices":[{"path":"/dev/sda","type":"disk","children":[
  {"path":"/dev/sda1","type":"part","fstype":"vfat",
   "parttype":"c12a7328-f81f-11d2-ba4b-00a0c93ec93b","parttypename":"EFI System"},
  {"path":"/dev/sda2","type":"part","fstype":null,
   "parttype":"0fc63daf-8483-4772-8e79-3d69d8477de4","parttypename":"Linux filesystem"},
  {"path":"/dev/sda3","type":"part","fstype":"ext4",
   "parttype":"0fc63daf-8483-4772-8e79-3d69d8477de4","parttypename":"Linux filesystem"},
  {"path":"/dev/sda4","type":"part","fstype":"swap",
   "parttype":"0657fd6d-a4ab-43c4-84e5-0933c84b4f4f","parttypename":"Linux swap"}
]}]}'

by_dev() { jq -e --arg d "$1" '.[] | select(.device == $d)'; }

# ── seed / pre-fill ─────────────────────────────────────────────────────────

@test "scan: every partition becomes an assignment entry" {
  run manual_partition_scan "$LSBLK"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = "4" ]
}

@test "scan: the ESP pre-fills /boot/efi + fat32" {
  parts="$(manual_partition_scan "$LSBLK")"
  echo "$parts" | by_dev /dev/sda1 | jq -e '.mountpoint == "/boot/efi"'
  echo "$parts" | by_dev /dev/sda1 | jq -e '.fs == "fat32"'
}

@test "scan: a swap partition pre-fills [swap]" {
  manual_partition_scan "$LSBLK" | by_dev /dev/sda4 \
    | jq -e '.mountpoint == "[swap]"'
}

@test "scan: a blank partition starts unassigned and formats by default" {
  parts="$(manual_partition_scan "$LSBLK")"
  echo "$parts" | by_dev /dev/sda2 | jq -e '.mountpoint == ""'
  echo "$parts" | by_dev /dev/sda2 | jq -e '.format == true'
}

@test "scan: a partition with existing data defaults to keep (no format)" {
  manual_partition_scan "$LSBLK" | by_dev /dev/sda3 | jq -e '.format == false'
}

@test "scan: a kept partition carries its existing filesystem" {
  # so the validator can judge whether the installer can mount it
  manual_partition_scan "$LSBLK" | by_dev /dev/sda3 | jq -e '.fs == "ext4"'
}

# ── filesystem cycle (editor primitive; supported values only) ──────────────

@test "cycle_fs: advances ext4 → xfs → btrfs and wraps" {
  [ "$(manual_partition_cycle_filesystem ext4)"  = "xfs" ]
  [ "$(manual_partition_cycle_filesystem xfs)"   = "btrfs" ]
  [ "$(manual_partition_cycle_filesystem btrfs)" = "ext4" ]
  [ "$(manual_partition_cycle_filesystem '')"    = "ext4" ]
  [ "$(manual_partition_cycle_filesystem ntfs)"  = "ext4" ]   # unknown → first supported
}

# ── edit ────────────────────────────────────────────────────────────────────

@test "set_field: assign the blank partition as root" {
  parts="$(manual_partition_scan "$LSBLK")"
  parts="$(manual_partition_set_field "$parts" /dev/sda2 mountpoint /)"
  echo "$parts" | by_dev /dev/sda2 | jq -e '.mountpoint == "/"'
}

@test "set_field: format is written as a JSON boolean, not a string" {
  parts="$(manual_partition_scan "$LSBLK")"
  parts="$(manual_partition_set_field "$parts" /dev/sda3 format true)"
  echo "$parts" | by_dev /dev/sda3 | jq -e '.format == true'
}

@test "set_field: an unknown device leaves the table unchanged" {
  parts="$(manual_partition_scan "$LSBLK")"
  run manual_partition_set_field "$parts" /dev/nope mountpoint /
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = "4" ]
}

@test "set_field output feeds straight into the layout planner shape" {
  # Assign root so the array is a valid planner input; assert the shape.
  parts="$(manual_partition_scan "$LSBLK")"
  parts="$(manual_partition_set_field "$parts" /dev/sda2 mountpoint /)"
  echo "$parts" | jq -e 'all(.[]; has("device") and has("mountpoint")
                                   and has("fs") and has("format"))'
}

# ── Proceed-only guard ──────────────────────────────────────────────────────

@test "kind_active: true when disk_config.kind is manual" {
  local state; state="$(config_state_set "$(config_state_new)" disk_config.kind '"manual"')"
  run manual_partition_kind_active "$state"
  [ "$status" -eq 0 ]
}

@test "kind_active: false on the default (auto) state" {
  run manual_partition_kind_active "$(config_state_new)"
  [ "$status" -ne 0 ]
}

# ── Config State write ──────────────────────────────────────────────────────

@test "store: the assignment lands at disk_config.partitions in state" {
  local parts state
  parts="$(manual_partition_set_field "$(manual_partition_scan "$LSBLK")" \
    /dev/sda2 mountpoint /)"
  state="$(manual_partition_store "$(config_state_new)" "$parts")"
  echo "$state" | jq -e '.disk_config.partitions | length == 4'
  echo "$state" | jq -e \
    '.disk_config.partitions[] | select(.device=="/dev/sda2") | .mountpoint == "/"'
}

@test "store: the stored shape is exactly the planner's input" {
  local parts state
  parts="$(manual_partition_scan "$LSBLK")"
  state="$(manual_partition_store "$(config_state_new)" "$parts")"
  # round-trips back out via the accessor path shape
  echo "$state" | jq -e '.disk_config.partitions
    | all(.[]; has("device") and has("mountpoint") and has("fs")
                                and has("format"))'
}

# ── auto-root: the largest unassigned partition becomes / ───────────────────

LSBLK_SZ='{"blockdevices":[{"path":"/dev/sda","type":"disk","children":[
  {"path":"/dev/sda1","type":"part","size":536870912,"fstype":"vfat",
   "parttype":"c12a7328-f81f-11d2-ba4b-00a0c93ec93b","parttypename":"EFI System"},
  {"path":"/dev/sda2","type":"part","size":2147483648,"fstype":null,
   "parttype":"x","parttypename":"Linux filesystem"},
  {"path":"/dev/sda3","type":"part","size":42949672960,"fstype":null,
   "parttype":"x","parttypename":"Linux filesystem"}
]}]}'

@test "autoroot: assigns / to the largest unassigned partition, fs ext4" {
  local parts
  parts="$(manual_partition_autoassign_root "$(manual_partition_scan "$LSBLK_SZ")")"
  echo "$parts" | by_dev /dev/sda3 | jq -e '.mountpoint == "/"'
  echo "$parts" | by_dev /dev/sda3 | jq -e '.fs == "ext4"'
  echo "$parts" | by_dev /dev/sda3 | jq -e '.format == true'
  # the smaller blank partition stays unassigned
  echo "$parts" | by_dev /dev/sda2 | jq -e '.mountpoint == ""'
}

@test "autoroot: a table that already names a root is unchanged" {
  local parts
  parts="$(manual_partition_set_field "$(manual_partition_scan "$LSBLK_SZ")" \
    /dev/sda2 mountpoint /)"
  run manual_partition_autoassign_root "$parts"
  [ "$status" -eq 0 ]
  echo "$output" | by_dev /dev/sda2 | jq -e '.mountpoint == "/"'
  echo "$output" | by_dev /dev/sda3 | jq -e '.mountpoint == ""'
}

# ── mountpoint cycle + row label (assignment editor primitives) ─────────────

@test "cycle: mountpoint advances through the set and wraps" {
  [ "$(manual_partition_cycle_mountpoint '')"          = "/" ]
  [ "$(manual_partition_cycle_mountpoint '/')"         = "/boot/efi" ]
  [ "$(manual_partition_cycle_mountpoint '/boot/efi')" = "/home" ]
  [ "$(manual_partition_cycle_mountpoint '/home')"     = "[swap]" ]
  [ "$(manual_partition_cycle_mountpoint '[swap]')"    = "" ]
  [ "$(manual_partition_cycle_mountpoint 'bogus')"     = "" ]
}

@test "row_label: renders device, mountpoint, fs and keep/format" {
  local row
  row="$(manual_partition_row_label \
    '{"device":"/dev/sda2","mountpoint":"/","fs":"ext4","format":true}')"
  [[ "$row" == *"/dev/sda2"* ]]
  [[ "$row" == *"/"* ]]
  [[ "$row" == *"ext4"* ]]
  [[ "$row" == *"[format]"* ]]
}

@test "row_label: an unassigned kept partition reads clearly" {
  local row
  row="$(manual_partition_row_label \
    '{"device":"/dev/sda9","mountpoint":"","fs":"","format":false}')"
  [[ "$row" == *"(unassigned)"* ]]
  [[ "$row" == *"[keep]"* ]]
}

# ── manual_partition_target_disk (ADR 0073: the operator picks the disk) ────

@test "manual_partition_target_disk: one candidate is used without asking" {
  picker_enum_disks() { echo /dev/disk/by-id/ata-ONLY; }
  readlink() { echo /dev/sda; }
  _manual_partition_choose_disk() { echo "asked" >&2; return 1; }
  run manual_partition_target_disk
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sda" ]
}

@test "manual_partition_target_disk: several candidates go to the picker" {
  # It used to take the first by-id disk silently — cfdisk on the wrong disk.
  picker_enum_disks() { printf '%s\n' /dev/disk/by-id/ata-A /dev/disk/by-id/ata-B; }
  readlink() { [[ "${*: -1}" == */ata-B ]] && echo /dev/sdb || echo /dev/sda; }
  _manual_partition_choose_disk() { printf '%s\n' "${@: -1}"; }
  run manual_partition_target_disk
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/sdb" ]
}

@test "manual_partition_target_disk: cancelling the picker cancels cfdisk" {
  picker_enum_disks() { printf '%s\n' /dev/disk/by-id/ata-A /dev/disk/by-id/ata-B; }
  _manual_partition_choose_disk() { return 1; }
  run manual_partition_target_disk
  [ "$status" -ne 0 ]
}
