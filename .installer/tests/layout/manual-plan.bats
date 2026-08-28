#!/usr/bin/env bats
# Tests for the Manual Partitioning planner/validator (ADR 0073) — the pure
# core that turns the operator's partitions[] assignment (JSON array of
# {device, mountpoint, fs, format}) into a validated format+mount plan, or
# aborts naming the offending condition. Partitions with no mountpoint are
# ignored. Pure: parses its JSON argument only, no disk access.
#
# Strategy mirrors nonzfs-plan.bats: stub error() to exit like production, feed
# an assignment, assert the emitted plan or the named rejection.

setup() {
  error() { echo "ERROR: $*" >&2; exit 1; }
  export -f error
  # shellcheck source=../../lib/layout/manual/plan.sh
  source "$BATS_TEST_DIRNAME/../../lib/layout/manual/plan.sh"
}

plan_field() { grep -E "^$1=" | cut -d= -f2; }

ESP='{"device":"/dev/sda1","mountpoint":"/boot/efi","fs":"fat32","format":true}'
ROOT='{"device":"/dev/sda2","mountpoint":"/","fs":"ext4","format":true}'

# ── tracer: a minimal ESP + root assignment plans cleanly ───────────────────

@test "plan: minimal ESP + root emits the device summary" {
  run manual_partition_plan "[$ESP,$ROOT]"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | plan_field root_device)" = "/dev/sda2" ]
  [ "$(printf '%s\n' "$output" | plan_field esp_device)"  = "/dev/sda1" ]
}

@test "plan: parents mount before children (root before /boot/efi)" {
  run manual_partition_plan "[$ESP,$ROOT]"
  [ "$status" -eq 0 ]
  local mounts
  mounts="$(printf '%s\n' "$output" | grep -c '^mount')"
  [ "$mounts" -eq 2 ]
  # root (/) is shallower than /boot/efi, so it must be emitted first.
  local first
  first="$(printf '%s\n' "$output" | grep '^mount' | head -n1 | cut -f3)"
  [ "$first" = "/" ]
}

@test "plan: a mount record carries device, mountpoint, fs and format flag" {
  run manual_partition_plan "[$ESP,$ROOT]"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qP '^mount\t/dev/sda2\t/\text4\ttrue$'
}

# ── /home + swap + keep-existing ────────────────────────────────────────────

@test "plan: swap partition emits a swap record, not a mount" {
  local swap='{"device":"/dev/sda3","mountpoint":"[swap]","fs":"","format":true}'
  run manual_partition_plan "[$ESP,$ROOT,$swap]"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qP '^swap\t/dev/sda3$'
  # [swap] never appears as a filesystem mount.
  ! printf '%s\n' "$output" | grep -q '^mount.*\[swap\]'
}

@test "plan: a kept (format=false) partition is mounted without formatting" {
  local home='{"device":"/dev/sda3","mountpoint":"/home","fs":"xfs","format":false}'
  run manual_partition_plan "[$ESP,$ROOT,$home]"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qP '^mount\t/dev/sda3\t/home\txfs\tfalse$'
}

@test "plan: an unassigned partition (no mountpoint) is ignored" {
  local spare='{"device":"/dev/sda9","mountpoint":"","fs":"ext4","format":false}'
  run manual_partition_plan "[$ESP,$ROOT,$spare]"
  [ "$status" -eq 0 ]
  ! printf '%s\n' "$output" | grep -q '/dev/sda9'
}

# ── rejections: each names the offending condition ──────────────────────────

@test "plan: no root is rejected" {
  run manual_partition_plan "[$ESP]"
  [ "$status" -ne 0 ]
  [[ "$output" =~ [Rr]oot ]]
}

@test "plan: two roots is rejected" {
  local root2='{"device":"/dev/sdb1","mountpoint":"/","fs":"ext4","format":true}'
  run manual_partition_plan "[$ESP,$ROOT,$root2]"
  [ "$status" -ne 0 ]
  [[ "$output" =~ [Rr]oot ]]
}

@test "plan: no ESP is rejected" {
  run manual_partition_plan "[$ROOT]"
  [ "$status" -ne 0 ]
  [[ "$output" =~ (ESP|/boot/efi) ]]
}

@test "plan: an ESP that is not FAT32 is rejected" {
  local badesp='{"device":"/dev/sda1","mountpoint":"/boot/efi","fs":"ext4","format":true}'
  run manual_partition_plan "[$badesp,$ROOT]"
  [ "$status" -ne 0 ]
  [[ "$output" =~ fat32 ]]
}

@test "plan: an empty assignment is rejected (no root)" {
  run manual_partition_plan "[]"
  [ "$status" -ne 0 ]
}

# ── out of bounds: unsupported filesystem / mountpoint → hard stop + help ────

@test "plan: an unsupported data filesystem is rejected, naming what's supported" {
  local bad='{"device":"/dev/sda3","mountpoint":"/home","fs":"ntfs","format":false}'
  run manual_partition_plan "[$ESP,$ROOT,$bad]"
  [ "$status" -ne 0 ]
  [[ "$output" =~ ntfs ]]           # names the offending fs
  [[ "$output" =~ ext4 ]]           # and lists the supported ones
  [[ "$output" =~ xfs ]]
  [[ "$output" =~ btrfs ]]
  [[ "$output" =~ cfdisk ]]         # and tells them to change cfdisk
}

@test "plan: an unsupported mountpoint is rejected" {
  local bad='{"device":"/dev/sda3","mountpoint":"/var","fs":"ext4","format":true}'
  run manual_partition_plan "[$ESP,$ROOT,$bad]"
  [ "$status" -ne 0 ]
  [[ "$output" =~ /var ]]
}

# ── the non-fatal problems reporter (for the live menu) ─────────────────────

@test "problems: a valid layout reports none (rc 0, empty)" {
  run manual_partition_problems "[$ESP,$ROOT]"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "problems: lists every issue at once without aborting" {
  local bad='{"device":"/dev/sda3","mountpoint":"/home","fs":"ntfs","format":false}'
  run manual_partition_problems "[$ROOT,$bad]"   # missing ESP + bad fs
  [ "$status" -eq 1 ]
  [[ "$output" =~ /boot/efi ]]
  [[ "$output" =~ ntfs ]]
}

@test "supported: the data filesystems are exactly ext4/xfs/btrfs" {
  run manual_supported_data_fs
  [ "$output" = "ext4
xfs
btrfs" ]
}
