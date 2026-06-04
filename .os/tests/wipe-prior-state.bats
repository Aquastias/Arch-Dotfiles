#!/usr/bin/env bats
# Tests for the prior-install-state detection in 02-wipe.sh.
#
# A failed 03-install.sh leaves the target's ZFS pools imported (altroot=/mnt)
# and the ESP + datasets mounted under /mnt. detect_disks() then skips the disk
# as "mounted". reset_prior_install_state() clears that first; the decision
# hinges on wipe_prior_state_present(), tested here.
#
# Strategy: source 02-wipe.sh (main() is guarded, so sourcing is inert) and
# override the two injectable seams to simulate state without touching the host.

setup() {
  # 02-wipe.sh sources lib/common.sh for these — but define no-ops first in
  # case that path changes; harmless if overridden by the real ones.
  info() { :; }; warn() { :; }; section() { :; }; error() { echo "ERR: $*" >&2; }

  # shellcheck source=../02-wipe.sh
  source "$BATS_TEST_DIRNAME/../02-wipe.sh"

  # 02-wipe.sh enables `set -Eeuo pipefail` and an ERR trap at source time;
  # relax both so assertion non-zero exits don't abort the test.
  set +eEuo pipefail
  trap - ERR
}

@test "present: a partition mounted under /mnt (the ESP case)" {
  _wipe_mounts_under_mnt()  { echo "/mnt/boot/efi"; }
  _wipe_pools_altroot_mnt() { :; }
  run wipe_prior_state_present
  [ "$status" -eq 0 ]
}

@test "present: a pool imported with altroot=/mnt" {
  _wipe_mounts_under_mnt()  { :; }
  _wipe_pools_altroot_mnt() { echo rpool; echo dpool; }
  run wipe_prior_state_present
  [ "$status" -eq 0 ]
}

@test "absent: nothing under /mnt and no /mnt-altroot pool" {
  _wipe_mounts_under_mnt()  { :; }
  _wipe_pools_altroot_mnt() { :; }
  run wipe_prior_state_present
  [ "$status" -ne 0 ]
}

@test "_wipe_mounts_under_mnt keeps /mnt mounts, excludes the live root /" {
  # Simulate findmnt's TARGET column: live root, archiso, and the install tree.
  findmnt() { printf '%s\n' / /run/archiso/bootmnt /mnt /mnt/boot/efi /mntfoo; }
  run _wipe_mounts_under_mnt
  [ "$status" -eq 0 ]
  grep -qx '/mnt'          <<<"$output"        # install root kept
  grep -qx '/mnt/boot/efi' <<<"$output"        # ESP kept
  ! grep -qx '/'                     <<<"$output"   # live root excluded
  ! grep -qx '/run/archiso/bootmnt'  <<<"$output"   # archiso excluded
  ! grep -qx '/mntfoo'               <<<"$output"   # no false prefix match
}

@test "_wipe_pools_altroot_mnt selects only altroot=/mnt pools" {
  # Simulate `zpool list -H -o name,altroot`: rpool/dpool are the install
  # scratch (altroot /mnt); tank is a pre-existing pool that must be left alone.
  zpool() { printf '%s\t%s\n' rpool /mnt dpool /mnt tank -; }
  run _wipe_pools_altroot_mnt
  [ "$status" -eq 0 ]
  grep -qx rpool <<<"$output"
  grep -qx dpool <<<"$output"
  ! grep -qx tank <<<"$output"
}

# Regression (live-boot-disk pollution): detect_disks's stdout is captured
# verbatim as the wipe list (`mapfile -t all_disks < <(detect_disks)`). When
# find_live_disk succeeds (e.g. booting from /dev/sr0), the "excluded" info line
# must NOT leak onto stdout, or it becomes a bogus disk that wipe_one_disk fails
# on. Captures stdout only — exactly as the real caller does.
@test "detect_disks: stdout is device paths only; diagnostics go to stderr" {
  find_live_disk() { echo /dev/sr0; }          # triggers the 'excluded' line
  info() { echo "[INFO] $*"; }                 # real-style: writes to stdout
  warn() { echo "[WARN] $*"; }
  lsblk() {
    case "$*" in
      *"-dno NAME,TYPE,RO"*) printf 'sda disk 0\nsdb disk 0\n' ;;
      *) : ;;                                   # no partitions for any disk
    esac
  }
  local out; out="$(detect_disks 2>/dev/null)"  # stdout only, as the caller sees
  [[ "$out" != *"[INFO]"* ]]
  [[ "$out" != *"Live boot"* ]]
  [[ "$out" == *"/dev/sda"* ]]
  [[ "$out" == *"/dev/sdb"* ]]
}
