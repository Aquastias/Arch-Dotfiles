#!/usr/bin/env bats
# security/rkhunter program — when the file-properties baseline is refreshed.

setup() {
  PROG="$BATS_TEST_DIRNAME/../../programs/security/rkhunter"
  INSTALL="$PROG/install.sh"
  SCAN="$PROG/scripts/rkhunter_scan.sh"
}

@test "the scheduled scan never re-baselines right before it checks" {
  # `--propupd` before `--check` accepted every changed binary as the new
  # baseline, so file-property tampering could never be reported.
  ! grep -q -- '--propupd' "$SCAN"
}

@test "the baseline is refreshed after each pacman transaction instead" {
  # Package upgrades change files legitimately; re-baselining at upgrade time
  # keeps the daily check from alarming on them.
  grep -q 'rkhunter-propupd.hook' "$INSTALL"
  grep -q 'Exec = /usr/bin/rkhunter --propupd -q' "$INSTALL"
  grep -q 'When = PostTransaction' "$INSTALL"
}
