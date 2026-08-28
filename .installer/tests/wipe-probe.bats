#!/usr/bin/env bats
# Tests for 02-wipe.sh's prior-state probe (_wipe_probe_disk) + skip_zeroed_disks.
#
# An install-driven wipe is handed the install's resolved target set. That set
# can name a disk that isn't present on the running machine (e.g. the config's
# os_pool lists disks for a different host than the one being installed). The
# probe must tolerate a non-existent / unreadable disk and report it blank,
# never trip the ERR trap — regression from the prior-state extraction, which
# moved the decision out of an `if is_disk_zeroed` context (where set -e was
# suspended) into a probe run under `set -Eeuo pipefail`.
#
# Enforcing setup (like wipe-live-medium.bats): source 02-wipe.sh and KEEP its
# set -Eeuo / ERR trap so a tripped trap actually fails the test.

setup() {
  # shellcheck source=../02-wipe.sh
  source "$BATS_TEST_DIRNAME/../02-wipe.sh"
  info() { :; }; warn() { :; }; section() { :; }
  # Avoid real blkid/findmnt scans for the live-medium check.
  is_live_medium() { return 1; }
}

@test "_wipe_probe_disk: a non-existent disk → blank fact, no ERR trap" {
  run _wipe_probe_disk /dev/no-such-disk-xyz
  [ "$status" -eq 0 ]
  [ "$output" = "/dev/no-such-disk-xyz|0||0|0" ]
}

@test "skip_zeroed_disks: a non-existent target is dropped as blank, no crash" {
  DISKS_TO_WIPE=(/dev/no-such-disk-xyz)
  skip_zeroed_disks
  [ "${#DISKS_TO_WIPE[@]}" -eq 0 ]
}
