#!/usr/bin/env bats
# Tests for .os/lib/common.sh — part_name partition-path derivation.

setup() {
  # shellcheck source=../lib/common.sh
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
}

# ── Kernel device nodes ─────────────────────────────────────────────────────

@test "part_name: nvme kernel node uses 'p' separator" {
  run part_name /dev/nvme0n1 1
  [ "$output" = "/dev/nvme0n1p1" ]
}

@test "part_name: mmcblk kernel node uses 'p' separator" {
  run part_name /dev/mmcblk0 2
  [ "$output" = "/dev/mmcblk0p2" ]
}

@test "part_name: sata kernel node has no separator" {
  run part_name /dev/sda 1
  [ "$output" = "/dev/sda1" ]
}

# ── Stable by-id symlinks (regression: mkfs.fat 'No such file') ─────────────

@test "part_name: by-id nvme symlink uses '-part' suffix" {
  run part_name /dev/disk/by-id/nvme-Samsung_SSD_980_S1 1
  [ "$output" = "/dev/disk/by-id/nvme-Samsung_SSD_980_S1-part1" ]
}

@test "part_name: by-id ata symlink uses '-part' suffix" {
  run part_name /dev/disk/by-id/ata-Crucial_MX500_X9 2
  [ "$output" = "/dev/disk/by-id/ata-Crucial_MX500_X9-part2" ]
}

@test "part_name: by-path symlink uses '-part' suffix" {
  run part_name /dev/disk/by-path/pci-0000:01:00.0-nvme-1 1
  [ "$output" = "/dev/disk/by-path/pci-0000:01:00.0-nvme-1-part1" ]
}
