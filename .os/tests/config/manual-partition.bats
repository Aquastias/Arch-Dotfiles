#!/usr/bin/env bats
# Tests for the Manual Partitioning assignment model (ADR 0073): seeding the
# assignment table from a disk's partition list (lsblk JSON), pre-filling the
# ESP and swap from partition type, editing an entry, and the Proceed-only
# terminal-action guard. Pure: JSON in, JSON out, no disk access. The cfdisk
# launch + live lsblk re-read are VM-verified (the manual matrix case).

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
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
  run manual_scan_partitions "$LSBLK"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = "4" ]
}

@test "scan: the ESP pre-fills /boot/efi + fat32" {
  parts="$(manual_scan_partitions "$LSBLK")"
  echo "$parts" | by_dev /dev/sda1 | jq -e '.mountpoint == "/boot/efi"'
  echo "$parts" | by_dev /dev/sda1 | jq -e '.fs == "fat32"'
}

@test "scan: a swap partition pre-fills [swap]" {
  manual_scan_partitions "$LSBLK" | by_dev /dev/sda4 \
    | jq -e '.mountpoint == "[swap]"'
}

@test "scan: a blank partition starts unassigned and formats by default" {
  parts="$(manual_scan_partitions "$LSBLK")"
  echo "$parts" | by_dev /dev/sda2 | jq -e '.mountpoint == ""'
  echo "$parts" | by_dev /dev/sda2 | jq -e '.format == true'
}

@test "scan: a partition with existing data defaults to keep (no format)" {
  manual_scan_partitions "$LSBLK" | by_dev /dev/sda3 | jq -e '.format == false'
}

@test "scan: a kept partition carries its existing filesystem" {
  # so the validator can judge whether the installer can mount it
  manual_scan_partitions "$LSBLK" | by_dev /dev/sda3 | jq -e '.fs == "ext4"'
}

# ── filesystem cycle (editor primitive; supported values only) ──────────────

@test "cycle_fs: advances ext4 → xfs → btrfs and wraps" {
  [ "$(manual_cycle_fs ext4)"  = "xfs" ]
  [ "$(manual_cycle_fs xfs)"   = "btrfs" ]
  [ "$(manual_cycle_fs btrfs)" = "ext4" ]
  [ "$(manual_cycle_fs '')"    = "ext4" ]
  [ "$(manual_cycle_fs ntfs)"  = "ext4" ]   # unknown → first supported
}

# ── edit ────────────────────────────────────────────────────────────────────

@test "set_field: assign the blank partition as root" {
  parts="$(manual_scan_partitions "$LSBLK")"
  parts="$(manual_set_field "$parts" /dev/sda2 mountpoint /)"
  echo "$parts" | by_dev /dev/sda2 | jq -e '.mountpoint == "/"'
}

@test "set_field: format is written as a JSON boolean, not a string" {
  parts="$(manual_scan_partitions "$LSBLK")"
  parts="$(manual_set_field "$parts" /dev/sda3 format true)"
  echo "$parts" | by_dev /dev/sda3 | jq -e '.format == true'
}

@test "set_field: an unknown device leaves the table unchanged" {
  parts="$(manual_scan_partitions "$LSBLK")"
  run manual_set_field "$parts" /dev/nope mountpoint /
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = "4" ]
}

@test "set_field output feeds straight into the layout planner shape" {
  # Assign root so the array is a valid planner input; assert the shape.
  parts="$(manual_scan_partitions "$LSBLK")"
  parts="$(manual_set_field "$parts" /dev/sda2 mountpoint /)"
  echo "$parts" | jq -e 'all(.[]; has("device") and has("mountpoint")
                                   and has("fs") and has("format"))'
}

# ── Proceed-only guard ──────────────────────────────────────────────────────

@test "kind_active: true when disk_config.kind is manual" {
  local s; s="$(cfgstate_set "$(cfgstate_new)" disk_config.kind '"manual"')"
  run manual_kind_active "$s"
  [ "$status" -eq 0 ]
}

@test "kind_active: false on the default (auto) state" {
  run manual_kind_active "$(cfgstate_new)"
  [ "$status" -ne 0 ]
}

# ── Config State write ──────────────────────────────────────────────────────

@test "store: the assignment lands at disk_config.partitions in state" {
  local parts state
  parts="$(manual_set_field "$(manual_scan_partitions "$LSBLK")" \
    /dev/sda2 mountpoint /)"
  state="$(manual_store_partitions "$(cfgstate_new)" "$parts")"
  echo "$state" | jq -e '.disk_config.partitions | length == 4'
  echo "$state" | jq -e \
    '.disk_config.partitions[] | select(.device=="/dev/sda2") | .mountpoint == "/"'
}

@test "store: the stored shape is exactly the planner's input" {
  local parts state
  parts="$(manual_scan_partitions "$LSBLK")"
  state="$(manual_store_partitions "$(cfgstate_new)" "$parts")"
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
  parts="$(manual_autoassign_root "$(manual_scan_partitions "$LSBLK_SZ")")"
  echo "$parts" | by_dev /dev/sda3 | jq -e '.mountpoint == "/"'
  echo "$parts" | by_dev /dev/sda3 | jq -e '.fs == "ext4"'
  echo "$parts" | by_dev /dev/sda3 | jq -e '.format == true'
  # the smaller blank partition stays unassigned
  echo "$parts" | by_dev /dev/sda2 | jq -e '.mountpoint == ""'
}

@test "autoroot: a table that already names a root is unchanged" {
  local parts
  parts="$(manual_set_field "$(manual_scan_partitions "$LSBLK_SZ")" \
    /dev/sda2 mountpoint /)"
  run manual_autoassign_root "$parts"
  [ "$status" -eq 0 ]
  echo "$output" | by_dev /dev/sda2 | jq -e '.mountpoint == "/"'
  echo "$output" | by_dev /dev/sda3 | jq -e '.mountpoint == ""'
}

# ── mountpoint cycle + row label (assignment editor primitives) ─────────────

@test "cycle: mountpoint advances through the set and wraps" {
  [ "$(manual_cycle_mountpoint '')"          = "/" ]
  [ "$(manual_cycle_mountpoint '/')"         = "/boot/efi" ]
  [ "$(manual_cycle_mountpoint '/boot/efi')" = "/home" ]
  [ "$(manual_cycle_mountpoint '/home')"     = "[swap]" ]
  [ "$(manual_cycle_mountpoint '[swap]')"    = "" ]
  [ "$(manual_cycle_mountpoint 'bogus')"     = "" ]
}

@test "row_label: renders device, mountpoint, fs and keep/format" {
  local r
  r="$(manual_row_label \
    '{"device":"/dev/sda2","mountpoint":"/","fs":"ext4","format":true}')"
  [[ "$r" == *"/dev/sda2"* ]]
  [[ "$r" == *"/"* ]]
  [[ "$r" == *"ext4"* ]]
  [[ "$r" == *"[format]"* ]]
}

@test "row_label: an unassigned kept partition reads clearly" {
  local r
  r="$(manual_row_label \
    '{"device":"/dev/sda9","mountpoint":"","fs":"","format":false}')"
  [[ "$r" == *"(unassigned)"* ]]
  [[ "$r" == *"[keep]"* ]]
}
