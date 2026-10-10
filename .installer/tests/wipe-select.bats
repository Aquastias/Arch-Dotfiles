#!/usr/bin/env bats
# Tests for the include-based disk selection in 02-wipe.sh.
#
# wipe_parse_selection is the pure core: an input string + the detected disk
# list → the included device paths. Empty input cancels (wipe nothing); `all`
# includes everything; otherwise 1-based indices, with garbage/out-of-range
# tokens skipped and the result deduped so a disk can't be wiped twice. The
# old model wiped everything by default and only let you exclude — this flips it.
#
# Enforcing setup (like wipe-live-medium.bats): source 02-wipe.sh and KEEP its
# set -Eeuo / ERR trap so a broken assertion actually fails the test; silence the
# cosmetic helpers only.

setup() {
  # shellcheck source=../02-wipe.sh
  source "$BATS_TEST_DIRNAME/../02-wipe.sh"
  info() { :; }; warn() { :; }; section() { :; }
}

@test "empty input selects nothing (default-cancel)" {
  run wipe_parse_selection "" /dev/sda /dev/sdb /dev/sdc
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "'all' selects every disk" {
  run wipe_parse_selection "all" /dev/sda /dev/sdb /dev/sdc
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "/dev/sda" ]
  [ "${lines[1]}" = "/dev/sdb" ]
  [ "${lines[2]}" = "/dev/sdc" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "'ALL' is case-insensitive" {
  run wipe_parse_selection "ALL" /dev/sda /dev/sdb
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "indices select the named disks (1-based)" {
  run wipe_parse_selection "1 3" /dev/sda /dev/sdb /dev/sdc
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "/dev/sda" ]
  [ "${lines[1]}" = "/dev/sdc" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "garbage and out-of-range tokens are skipped" {
  run wipe_parse_selection "0 9 x 2" /dev/sda /dev/sdb /dev/sdc
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "/dev/sdb" ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "a repeated index is selected once (no double-wipe)" {
  run wipe_parse_selection "2 2" /dev/sda /dev/sdb /dev/sdc
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "/dev/sdb" ]
  [ "${#lines[@]}" -eq 1 ]
}

# ── parse_arguments: positional disk paths become explicit targets ──────────
# Run in-process (no `run`) so the global TARGETS array is observable.

@test "parse_arguments: positional disks become TARGETS, -y is unattended" {
  parse_arguments -y /dev/sda /dev/nvme0n1
  [ "${TARGETS[*]}" = "/dev/sda /dev/nvme0n1" ]
  [ "${INSTALL_UNATTENDED}" = "1" ]
}

@test "parse_arguments with no positional args leaves TARGETS empty" {
  parse_arguments -y
  [ "${#TARGETS[@]}" -eq 0 ]
}
