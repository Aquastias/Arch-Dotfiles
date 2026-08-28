#!/usr/bin/env bats
# Tests for .os/lib/chroot/udisks.sh — udisks-ignore rule for ZFS members.
#
# The rule stops a udisks2-backed file manager (KDE Solid/Dolphin, …) from
# listing ZFS pool members as removable drives, which today prompt for a
# password then fail with "zfs_member not configured in kernel" (ADR 0031,
# pool-owners issue 01). The emitter is pure (prints the rule); the writer is
# the thin I/O step the Chroot Configuration Module runs on every install.

setup() {
  # shellcheck source=../../lib/chroot/udisks.sh
  source "$BATS_TEST_DIRNAME/../../lib/chroot/udisks.sh"
}

# ── udisks_zfs_ignore_rule (pure emitter) ────────────────────────────────────

@test "udisks_zfs_ignore_rule: targets zfs_member partitions" {
  run udisks_zfs_ignore_rule
  [ "$status" -eq 0 ]
  [[ "$output" == *"zfs_member"* ]]
}

@test "udisks_zfs_ignore_rule: sets the udisks ignore flag" {
  run udisks_zfs_ignore_rule
  [ "$status" -eq 0 ]
  [[ "$output" == *'UDISKS_IGNORE}="1"'* ]]
}

# ── udisks_write_zfs_ignore_rule (thin I/O) ──────────────────────────────────

@test "udisks_write_zfs_ignore_rule: writes the rule under udev/rules.d" {
  local root="$BATS_TEST_TMPDIR/root"
  run udisks_write_zfs_ignore_rule "$root"
  [ "$status" -eq 0 ]
  local f
  f="$(find "$root/etc/udev/rules.d" -name '*.rules' 2>/dev/null | head -1)"
  [ -f "$f" ]
  grep -q 'zfs_member' "$f"
  grep -q 'UDISKS_IGNORE}="1"' "$f"
}
