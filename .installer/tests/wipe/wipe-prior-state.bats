#!/usr/bin/env bats
# Unit tests for lib/wipe/prior-state.sh — the pure prior-state decision.
#
# Splits today's is_disk_zeroed into a probe (block-device I/O, stays in the
# orchestrator) and this pure decision over the probed facts. No real device is
# touched here: every input is a plain fact value.
#   wipe_disk_dirty SIG NPARTS NONZERO → exit 0 dirty (needs wipe) / 1 blank
#   wipe_select_to_wipe (TAB facts on stdin) → disks to wipe (dirty, not live)

setup() {
  # shellcheck source=../../lib/wipe/prior-state.sh
  source "$BATS_TEST_DIRNAME/../../lib/wipe/prior-state.sh"
}

@test "wipe_disk_dirty: no signature, no partitions, all-zero is blank" {
  run wipe_disk_dirty "" 0 0
  [ "$status" -eq 1 ]
}

@test "wipe_disk_dirty: a filesystem/ZFS/LVM/MD signature is dirty" {
  run wipe_disk_dirty "zfs_member" 0 0
  [ "$status" -eq 0 ]
}

@test "wipe_disk_dirty: child partitions (a partition table) are dirty" {
  run wipe_disk_dirty "" 2 0
  [ "$status" -eq 0 ]
}

@test "wipe_disk_dirty: a non-zero sampled window is dirty" {
  run wipe_disk_dirty "" 0 1
  [ "$status" -eq 0 ]
}

# ── wipe_select_to_wipe: the set over facts ──────────────────────────────────
# Facts are '|'-separated, one disk per line: disk|is_live|sig|nparts|nonzero.
# A non-whitespace delimiter keeps an empty sig field from collapsing.

@test "wipe_select_to_wipe: keeps a dirty disk, drops a blank one" {
  run wipe_select_to_wipe <<'FACTS'
/dev/sda|0|zfs_member|0|0
/dev/sdb|0||0|0
FACTS
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "/dev/sda" ]
}

@test "wipe_select_to_wipe: excludes the live medium even when it is dirty" {
  run wipe_select_to_wipe <<'FACTS'
/dev/sda|0|zfs_member|0|0
/dev/sdb|1|zfs_member|1|1
FACTS
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "/dev/sda" ]
}

@test "wipe_select_to_wipe: mixed set is exactly the dirty non-live disks, in order" {
  run wipe_select_to_wipe <<'FACTS'
/dev/sda|0|zfs_member|0|0
/dev/sdb|0||0|0
/dev/nvme0n1|1|zfs_member|3|1
/dev/sdc|0||1|0
/dev/sdd|0||0|1
FACTS
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[0]}" = "/dev/sda" ]   # signature → dirty
  [ "${lines[1]}" = "/dev/sdc" ]   # partition table → dirty
  [ "${lines[2]}" = "/dev/sdd" ]   # non-zero data → dirty
}
