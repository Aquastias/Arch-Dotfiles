#!/usr/bin/env bats
# Tests for .os/lib/chroot/zfs-import.sh — decouple the post-boot ZFS import
# services from the deprecated systemd-udev-settle (ADR 0030, boot-import
# issue 01).
#
# A reset drop-in (Requires=) does NOT actually remove a dependency declared in
# the unit's main file on systemd 260 (verified on a booted install — the
# services still required systemd-udev-settle). So instead we generate a FULL
# replacement unit at /etc/systemd/system/, which completely shadows the
# /usr/lib unit (no merge), with the settle dependency filtered out. The filter
# is pure; the writer is the thin I/O step the Chroot Configuration Module runs.

setup() {
  # shellcheck source=../lib/chroot/zfs-import.sh
  source "$BATS_TEST_DIRNAME/../lib/chroot/zfs-import.sh"
}

# A representative shipped zfs-import-cache.service (archzfs). settle appears as
# the sole token on its own Requires=/After= lines, plus a combined After= line
# to prove token-level (not just whole-line) removal.
sample_unit() {
  cat <<'UNIT'
[Unit]
Description=Import ZFS pools by cache file
DefaultDependencies=no
Requires=systemd-udev-settle.service
After=systemd-udev-settle.service
After=cryptsetup.target systemd-udev-settle.service
After=multipathd.service
Before=zfs-import.target
ConditionFileNotEmpty=/etc/zfs/zpool.cache

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/zpool import -c /etc/zfs/zpool.cache -aN

[Install]
WantedBy=zfs-import.target
UNIT
}

# ── zfs_import_strip_settle (pure filter) ────────────────────────────────────

@test "strip_settle: removes systemd-udev-settle entirely" {
  run zfs_import_strip_settle <<<"$(sample_unit)"
  [ "$status" -eq 0 ]
  [[ "$output" != *"systemd-udev-settle"* ]]
}

@test "strip_settle: keeps other After= ordering (cryptsetup, multipathd)" {
  run zfs_import_strip_settle <<<"$(sample_unit)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"After=cryptsetup.target"* ]]
  [[ "$output" == *"After=multipathd.service"* ]]
}

@test "strip_settle: drops a directive line emptied by the removal" {
  # Requires= had only settle, so the whole line goes (no dangling 'Requires=').
  run zfs_import_strip_settle <<<"$(sample_unit)"
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\nRequires='* ]]
}

@test "strip_settle: preserves non-dependency content verbatim" {
  run zfs_import_strip_settle <<<"$(sample_unit)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Description=Import ZFS pools by cache file"* ]]
  [[ "$output" == *"ExecStart=/usr/bin/zpool import -c /etc/zfs/zpool.cache -aN"* ]]
  [[ "$output" == *"[Install]"* ]]
  [[ "$output" == *"WantedBy=zfs-import.target"* ]]
}

# ── zfs_import_write_settle_overrides (thin I/O) ─────────────────────────────

@test "write_settle_overrides: writes a settle-free /etc unit for cache" {
  local root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root/usr/lib/systemd/system"
  sample_unit > "$root/usr/lib/systemd/system/zfs-import-cache.service"
  run zfs_import_write_settle_overrides "$root"
  [ "$status" -eq 0 ]
  local dst="$root/etc/systemd/system/zfs-import-cache.service"
  [ -f "$dst" ]
  ! grep -q 'systemd-udev-settle' "$dst"
  grep -q '^ExecStart=' "$dst"          # full unit, not a drop-in
}

@test "write_settle_overrides: writes scan too when shipped" {
  local root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root/usr/lib/systemd/system"
  sample_unit > "$root/usr/lib/systemd/system/zfs-import-scan.service"
  run zfs_import_write_settle_overrides "$root"
  [ "$status" -eq 0 ]
  [ -f "$root/etc/systemd/system/zfs-import-scan.service" ]
  ! grep -q 'systemd-udev-settle' \
    "$root/etc/systemd/system/zfs-import-scan.service"
}

@test "write_settle_overrides: skips gracefully when a unit is not shipped" {
  local root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root/usr/lib/systemd/system"   # no unit files present
  run zfs_import_write_settle_overrides "$root"
  [ "$status" -eq 0 ]
  [ ! -e "$root/etc/systemd/system/zfs-import-cache.service" ]
}
