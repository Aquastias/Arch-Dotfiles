#!/usr/bin/env bats
# Integration tests for 02-wipe.sh's use of the Live-Medium Detector:
#   - detect_disks never lists the live medium (and its stdout stays clean);
#   - assert_no_live_medium_targets is the belt-and-suspenders hard guard that
#     aborts the wipe if a live-medium disk is somehow targeted.
#
# Enforcing setup: we source 02-wipe.sh and KEEP its `set -Eeuo pipefail` + ERR
# trap. A failing assertion then trips _on_error (exit 1) and the test fails for
# real — unlike wipe-prior-state.bats, whose `trap - ERR` blinds bats. The
# Detector itself is overridden at the is_live_medium / live_medium_disks /
# seam level, so no real USB or block device is touched.

setup() {
  # shellcheck source=../02-wipe.sh
  source "$BATS_TEST_DIRNAME/../02-wipe.sh"
  # Silence cosmetic helpers; keep the real `error` (the guard relies on it).
  info() { :; }; warn() { :; }; section() { :; }
}

# ── Hard guard ──────────────────────────────────────────────────────────────

@test "hard guard: wipe aborts and names the disk when a target is live" {
  is_live_medium() { [[ "$1" == /dev/sdb ]]; }   # sdb is the live USB
  DISKS_TO_WIPE=(/dev/sda /dev/sdb)
  run assert_no_live_medium_targets
  [ "$status" -ne 0 ]
  [[ "$output" == *"/dev/sdb"* ]]
}

@test "hard guard: wipe proceeds when no target is the live medium" {
  is_live_medium() { return 1; }                 # nothing is live
  DISKS_TO_WIPE=(/dev/sda /dev/sdc)
  run assert_no_live_medium_targets
  [ "$status" -eq 0 ]
}

# ── detect_disks exclusion (+ stdout-cleanliness regression) ─────────────────
# detect_disks's stdout is captured verbatim as the wipe list, so the live
# medium must never appear there and the "excluded" notice must stay on stderr.

@test "detect_disks: excludes the live medium; stdout is device paths only" {
  live_medium_disks() { echo /dev/sdb; }         # sdb is the live USB
  info() { echo "[INFO] $*"; }                    # would leak if not >&2-routed
  warn() { echo "[WARN] $*"; }
  lsblk() {
    case "$*" in
      *"-dno NAME,TYPE,RO"*) printf 'sda disk 0\nsdb disk 0\nsdc disk 0\n' ;;
      *) : ;;                                      # no partitions for any disk
    esac
  }
  local out; out="$(detect_disks 2>/dev/null)"    # stdout only, as caller sees
  [[ "$out" == *"/dev/sda"* ]]
  [[ "$out" == *"/dev/sdc"* ]]
  [[ "$out" != *"/dev/sdb"* ]]                     # live medium excluded
  [[ "$out" != *"[INFO]"* ]]                       # diagnostics didn't leak
}
