#!/usr/bin/env bats
# Tests for lib/boot/zfs-arc.sh — the ZFS ARC cap cmdline fragment (ADR 0161).
#
# Maps the Install State wire format to `zfs.zfs_arc_max=<bytes>` (Arch Wiki:
# ZFS, ARC). Pure JSON-in / string-out, asserted on the emitted string.

setup() {
  # shellcheck source=../../lib/boot/zfs-arc.sh
  source "$BATS_TEST_DIRNAME/../../lib/boot/zfs-arc.sh"
}

@test "4G on zfs → the byte value the wiki's parameter takes" {
  run zfs_arc_cmdline_params '{"filesystem":"zfs","zfs":{"arc_max":"4G"}}'
  [ "$status" -eq 0 ]
  [ "$output" = "zfs.zfs_arc_max=4294967296" ]
}

@test "the wiki's 512MiB example" {
  run zfs_arc_cmdline_params '{"filesystem":"zfs","zfs":{"arc_max":"512M"}}'
  [ "$output" = "zfs.zfs_arc_max=536870912" ]
}

@test "unset → empty (ZFS default)" {
  run zfs_arc_cmdline_params '{"filesystem":"zfs","zfs":{"arc_max":""}}'
  [ "$output" = "" ]
}

@test "non-zfs root → empty even when set" {
  run zfs_arc_cmdline_params '{"filesystem":"btrfs","zfs":{"arc_max":"4G"}}'
  [ "$output" = "" ]
}

@test "zfs_arc_max_bytes: plain bytes and K/M/G/T suffixes" {
  [ "$(zfs_arc_max_bytes 1048576)" = "1048576" ]
  [ "$(zfs_arc_max_bytes 64K)" = "65536" ]
  [ "$(zfs_arc_max_bytes 1T)" = "1099511627776" ]
}

@test "zfs_arc_max_bytes: rejects malformed sizes" {
  run zfs_arc_max_bytes 4GB
  [ "$status" -ne 0 ]
  run zfs_arc_max_bytes -1G
  [ "$status" -ne 0 ]
  run zfs_arc_max_bytes 0
  [ "$status" -ne 0 ]
}
