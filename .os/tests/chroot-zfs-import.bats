#!/usr/bin/env bats
# Tests for .os/lib/chroot/zfs-import.sh — decouple the post-boot ZFS import
# services from the deprecated systemd-udev-settle (ADR 0030, boot-import
# issue 01). The emitter is pure (prints a systemd drop-in); the writer is the
# thin I/O step the Chroot Configuration Module runs on every install.

setup() {
  # shellcheck source=../lib/chroot/zfs-import.sh
  source "$BATS_TEST_DIRNAME/../lib/chroot/zfs-import.sh"
}

# ── zfs_import_settle_dropin (pure emitter) ──────────────────────────────────

@test "zfs_import_settle_dropin: drops the systemd-udev-settle dependency" {
  run zfs_import_settle_dropin
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Unit]"* ]]
  [[ "$output" != *"systemd-udev-settle"* ]]
}

@test "zfs_import_settle_dropin: resets the Requires list to empty" {
  # An empty Requires= assignment clears the unit's whole requires list, so a
  # stalled/missing dependency can no longer fail the import with
  # "Dependency failed".
  run zfs_import_settle_dropin
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\nRequires='* ]]
}

@test "zfs_import_settle_dropin: keeps cryptsetup ordering" {
  # Resetting After= would also drop ordering after cryptsetup.target; re-add
  # it so encrypted pools still order correctly (no regression).
  run zfs_import_settle_dropin
  [ "$status" -eq 0 ]
  [[ "$output" == *"After=cryptsetup.target"* ]]
}

# ── zfs_import_write_settle_dropins (thin I/O) ───────────────────────────────

@test "zfs_import_write_settle_dropins: drops in for zfs-import-cache" {
  local root="$BATS_TEST_TMPDIR/root"
  run zfs_import_write_settle_dropins "$root"
  [ "$status" -eq 0 ]
  local d="$root/etc/systemd/system/zfs-import-cache.service.d"
  local f
  f="$(find "$d" -name '*.conf' 2>/dev/null | head -1)"
  [ -f "$f" ]
  grep -q '^\[Unit\]' "$f"
  ! grep -q 'systemd-udev-settle' "$f"
}

@test "zfs_import_write_settle_dropins: drops in for zfs-import-scan too" {
  local root="$BATS_TEST_TMPDIR/root"
  run zfs_import_write_settle_dropins "$root"
  [ "$status" -eq 0 ]
  local d="$root/etc/systemd/system/zfs-import-scan.service.d"
  local f
  f="$(find "$d" -name '*.conf' 2>/dev/null | head -1)"
  [ -f "$f" ]
  ! grep -q 'systemd-udev-settle' "$f"
}
