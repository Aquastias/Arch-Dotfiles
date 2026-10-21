#!/usr/bin/env bats
# Tests for .installer/lib/chroot/zfs-import.sh — decouple the post-boot ZFS
# import
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
  # shellcheck source=../../lib/chroot/zfs-import.sh
  source "$BATS_TEST_DIRNAME/../../lib/chroot/zfs-import.sh"
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
  local unit_file="$root/etc/systemd/system/zfs-import-cache.service"
  [ -f "$unit_file" ]
  ! grep -q 'systemd-udev-settle' "$unit_file"
  grep -q '^ExecStart=' "$unit_file"          # full unit, not a drop-in
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

# ── zfs_import_write_load_key_template (encrypted DATA pool boot key-load, ADR 0043) ─
# Upstream OpenZFS ships no zfs-load-key@.service; configure.sh enables it per
# file-keyed encrypted data pool so the pool auto-loads its key from the keyfile
# on the already-mounted root BEFORE zfs-mount.service mounts the datasets (no
# second prompt). The root pool is unlocked by the initramfs, not this unit.

@test "load_key_template: writes the zfs-load-key@ template under /etc" {
  local root="$BATS_TEST_TMPDIR/root"
  run zfs_import_write_load_key_template "$root"
  [ "$status" -eq 0 ]
  [ -f "$root/etc/systemd/system/zfs-load-key@.service" ]
}

@test "load_key_template: loads the instance key before zfs-mount.service" {
  local root="$BATS_TEST_TMPDIR/root"
  zfs_import_write_load_key_template "$root"
  local unit_file="$root/etc/systemd/system/zfs-load-key@.service"
  grep -q '^ExecStart=/usr/bin/zfs load-key %i' "$unit_file"
  grep -q '^Before=zfs-mount.service' "$unit_file"
  grep -q '^WantedBy=zfs-mount.service' "$unit_file"
}

# ── zfs_import_write_list_cache (zfs-mount-generator cache, correct columns) ─────────
# The generator parses each cache line positionally with the OpenZFS cacher's
# exact -o property set. The repo's old 8-column set was MISALIGNED (`readonly`
# where the generator expects `devices`), so the generator bailed (exit 1). The
# writer must emit the canonical 20-column order (12 real props + 8
# org.openzfs.systemd:* user-props).

CANON_COLS='name,mountpoint,canmount,atime,relatime,devices,exec,readonly,setuid,nbmand,encroot,keylocation,org.openzfs.systemd:requires,org.openzfs.systemd:requires-mounts-for,org.openzfs.systemd:before,org.openzfs.systemd:after,org.openzfs.systemd:wanted-by,org.openzfs.systemd:required-by,org.openzfs.systemd:nofail,org.openzfs.systemd:ignore'

@test "list_cache: passes zfs the canonical 20-column -o property set" {
  local cache_directory="$BATS_TEST_TMPDIR/cache"
  # Stub zfs: record the -o argument, emit a fake cache line to stdout.
  zfs() {
    local previous_argument=""
    for argument in "$@"; do
      [[ "$previous_argument" == "-o" ]] && printf '%s' "$argument" > "$BATS_TEST_TMPDIR/cols"
      previous_argument="$argument"
    done
    printf 'rpool\t/\toff\n'
  }
  zfs_import_write_list_cache rpool "$cache_directory"
  [ "$(cat "$BATS_TEST_TMPDIR/cols")" = "$CANON_COLS" ]
}

@test "list_cache: writes the cache file named for the pool" {
  local cache_directory="$BATS_TEST_TMPDIR/cache"
  zfs() { printf 'rpool\t/\toff\n'; }
  zfs_import_write_list_cache rpool "$cache_directory"
  [ -f "$cache_directory/rpool" ]
}

# no-shell 20261007 / noctalia-greeter 20261021: `zfs mount -a` aborts now and
# then in libzfs (a parallel-mount race). Restart= retried only after the
# failed start job had released every After= unit — the /persist bind mounts
# then failed on a missing source. The retry lives inside the start job.

_mount_retry_dropin() {
  local root_directory="$BATS_TEST_TMPDIR/root"
  zfs_import_write_mount_retry_dropin "$root_directory"
  printf '%s\n' \
    "$root_directory/etc/systemd/system/zfs-mount.service.d/10-retry.conf"
}

# Run the drop-in's ExecStart as systemd would ($$ → $) with a `zfs` stub that
# fails its first <fails> calls; sleep is stubbed out.
_mount_retry_run() {
  local fails="$1" dropin_file bin="$BATS_TEST_TMPDIR/bin" script
  dropin_file="$(_mount_retry_dropin)"
  mkdir -p "$bin"
  printf '#!/bin/sh\necho "$*" >> "%s/calls"\n[ "$(grep -c . "%s/calls")" -gt %s ]\n' \
    "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" "$fails" > "$bin/zfs"
  printf '#!/bin/sh\n' > "$bin/sleep"
  chmod +x "$bin/zfs" "$bin/sleep"
  script="$(awk -F"'" '/^ExecStart=\/bin\/sh -c / { print $2 }' \
    "$dropin_file")"
  script="${script//\$\$/\$}"
  PATH="$bin:$PATH" run /bin/sh -c "$script"
}

@test "mount_retry_dropin: replaces ExecStart, no Restart=" {
  local dropin_file
  dropin_file="$(_mount_retry_dropin)"
  grep -qx 'ExecStart=' "$dropin_file"
  ! grep -q '^Restart' "$dropin_file"
}

@test "mount_retry_dropin: a crashed zfs mount -a is retried in the job" {
  _mount_retry_run 2
  [ "$status" -eq 0 ]
  [ "$(grep -cx 'mount -a' "$BATS_TEST_TMPDIR/calls")" -eq 3 ]
}

@test "mount_retry_dropin: gives up after 3 attempts" {
  _mount_retry_run 9
  [ "$status" -ne 0 ]
  [ "$(grep -c . "$BATS_TEST_TMPDIR/calls")" -eq 3 ]
}

@test "configure writes the zfs-mount retry drop-in" {
  grep -q 'zfs_import_write_mount_retry_dropin ""' \
    "$BATS_TEST_DIRNAME/../../lib/chroot/configure.sh"
}
