#!/usr/bin/env bats
# Tests for .installer/lib/zfs/pool-owners.sh — the Owners Resolver (pure, ADR
# 0031).
#
# The resolver decides, for one pool, how its mountpoint becomes usable by a
# human: who owns it (chown), whether POSIX ACLs are needed, which users get a
# ~/Disks/<pool> symlink, and whether the declaration is valid. It never
# touches the filesystem — the Owners Applier does that. Tests assert the
# external decision, never how it is computed.
#
# Input contract shared by every accessor:
#   $1 owners    space-separated tokens; a bare name is a user, @name a group;
#                "" means owners was omitted
#   $2 users     space-separated declared usernames, Primary User first
#   $3 groupmap  space-separated "group:member1,member2" pairs ("" when none)

setup() {
  # shellcheck source=../../lib/zfs/pool-owners.sh
  source "$BATS_TEST_DIRNAME/../../lib/zfs/pool-owners.sh"
}

# ── zfs_pool_owners_base ─────────────────────────────────────────────────────────

@test "zfs_pool_owners_base: omitted owners defaults to the Primary User" {
  run zfs_pool_owners_base "" "alice bob"
  [ "$status" -eq 0 ]
  [ "$output" = "alice" ]
}

@test "zfs_pool_owners_base: a single named user owns the pool" {
  run zfs_pool_owners_base "carol" "alice bob carol"
  [ "$status" -eq 0 ]
  [ "$output" = "carol" ]
}

@test "zfs_pool_owners_base: first listed user wins even after a @group" {
  run zfs_pool_owners_base "@family bob alice" "alice bob"
  [ "$status" -eq 0 ]
  [ "$output" = "bob" ]
}

# ── zfs_pool_owners_mode ─────────────────────────────────────────────────────────

@test "zfs_pool_owners_mode: omitted owners with a Primary User is a chown" {
  run zfs_pool_owners_mode "" "alice bob"
  [ "$status" -eq 0 ]
  [ "$output" = "chown" ]
}

@test "zfs_pool_owners_mode: omitted owners on a userless host stays root" {
  run zfs_pool_owners_mode "" ""
  [ "$status" -eq 0 ]
  [ "$output" = "root" ]
}

@test "zfs_pool_owners_mode: a single named user is a chown (no ACL)" {
  run zfs_pool_owners_mode "carol" "alice bob carol"
  [ "$status" -eq 0 ]
  [ "$output" = "chown" ]
}

@test "zfs_pool_owners_mode: more than one user needs ACLs" {
  run zfs_pool_owners_mode "alice bob" "alice bob"
  [ "$status" -eq 0 ]
  [ "$output" = "acl" ]
}

@test "zfs_pool_owners_mode: any @group needs ACLs" {
  run zfs_pool_owners_mode "alice @family" "alice" "family:alice,bob"
  [ "$status" -eq 0 ]
  [ "$output" = "acl" ]
}

# ── zfs_pool_owners_access_users (drives ~/Disks/<pool> symlinks) ─────────────────

@test "zfs_pool_owners_access_users: omitted owners is just the Primary User" {
  run zfs_pool_owners_access_users "" "alice bob"
  [ "$status" -eq 0 ]
  [ "$output" = "alice" ]
}

@test "zfs_pool_owners_access_users: userless host grants access to no one" {
  run zfs_pool_owners_access_users "" ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "zfs_pool_owners_access_users: a single named user gets the only symlink" {
  run zfs_pool_owners_access_users "carol" "alice bob carol"
  [ "$status" -eq 0 ]
  [ "$output" = "carol" ]
}

@test "zfs_pool_owners_access_users: union of listed users and @group members" {
  run zfs_pool_owners_access_users "alice @family" "alice bob carol" \
    "family:bob,carol"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "alice" ]
  [[ "$output" == *bob* ]]
  [[ "$output" == *carol* ]]
  [ "${#lines[@]}" -eq 3 ]
}

@test "zfs_pool_owners_access_users: a user in both list and @group appears once" {
  run zfs_pool_owners_access_users "alice @family" "alice bob" "family:alice,bob"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
}

# ── zfs_pool_owners_acl_entries (the setfacl plan for ACL pools) ─────────────────

@test "zfs_pool_owners_acl_entries: user gets an rwx entry + default mirror" {
  run zfs_pool_owners_acl_entries "alice bob"
  [ "$status" -eq 0 ]
  [[ "$output" == *"u:alice:rwx"* ]]
  [[ "$output" == *"u:bob:rwx"* ]]
  [[ "$output" == *"d:u:alice:rwx"* ]]
  [[ "$output" == *"d:u:bob:rwx"* ]]
}

@test "zfs_pool_owners_acl_entries: @group gets a group rwx entry + default mirror" {
  run zfs_pool_owners_acl_entries "@family"
  [ "$status" -eq 0 ]
  [[ "$output" == *"g:family:rwx"* ]]
  [[ "$output" == *"d:g:family:rwx"* ]]
}

@test "zfs_pool_owners_acl_entries: sets the ACL mask to rwx (incl. default)" {
  run zfs_pool_owners_acl_entries "alice @family"
  [ "$status" -eq 0 ]
  [[ "$output" == *"m::rwx"* ]]
  [[ "$output" == *"d:m::rwx"* ]]
}

# ── zfs_pool_owners_validate (drives layout_validate, ADR 0031) ──────────────────

@test "zfs_pool_owners_validate: omitted owners is always valid" {
  run zfs_pool_owners_validate "" "alice bob" ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "zfs_pool_owners_validate: a declared user is valid" {
  run zfs_pool_owners_validate "alice" "alice bob" ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "zfs_pool_owners_validate: an undeclared user fails with a reason" {
  run zfs_pool_owners_validate "carol" "alice bob" ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"carol"* ]]
}

@test "zfs_pool_owners_validate: a @group with members is valid" {
  run zfs_pool_owners_validate "alice @family" "alice bob" "family:alice,bob"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "zfs_pool_owners_validate: a @group with no members fails with a reason" {
  run zfs_pool_owners_validate "@family" "alice bob" ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"family"* ]]
}

# ── _pool_owners_group_mounts (independent → per-disk child mounts) ───────────

@test "_pool_owners_group_mounts: non-independent is the single mountpoint" {
  run _pool_owners_group_mounts /data/media mirror 2
  [ "$status" -eq 0 ]
  [ "$output" = "/data/media" ]
}

@test "_pool_owners_group_mounts: independent expands to per-disk children" {
  run _pool_owners_group_mounts /data/media independent 3
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "/data/media/disk1" ]
  [ "${lines[1]}" = "/data/media/disk2" ]
  [ "${lines[2]}" = "/data/media/disk3" ]
  [ "${#lines[@]}" -eq 3 ]
}

# ── zfs_pool_owners_apply_mount (thin I/O, host-side numeric translation) ─────────
# The applier runs on the live ISO against the altroot-mounted system, so it
# must resolve each owner to a numeric UID/GID from the INSTALLED passwd/group
# (the ISO has no knowledge of the chroot's users). chown/chmod/setfacl are
# stubbed (they need root); ln/mkdir run for real so the ~/Disks symlink is
# observable. alice's gid (9000) differs from her uid (1000) to prove the
# applier uses the primary GID (passwd field 4), not the uid.

_apply_env() {
  MOUNT_ROOT="$BATS_TEST_TMPDIR/mnt"
  POOL_OWNERS_HOME_BASE="/home"
  CHOWN_LOG="$BATS_TEST_TMPDIR/chown.log"; : > "$CHOWN_LOG"
  mkdir -p "${MOUNT_ROOT}/data/tank0" "${MOUNT_ROOT}/etc"
  cat > "${MOUNT_ROOT}/etc/passwd" <<'PW'
root:x:0:0::/root:/bin/bash
alice:x:1000:9000::/home/alice:/bin/bash
bob:x:1001:1001::/home/bob:/bin/bash
carol:x:1002:1002::/home/carol:/bin/bash
PW
  cat > "${MOUNT_ROOT}/etc/group" <<'GR'
root:x:0:
alice:x:9000:
family:x:1500:bob,carol
GR
  chown() { printf '%s\n' "$*" >> "$CHOWN_LOG"; }
  chmod() { :; }
  setfacl() { :; }
  warn()  { :; }
  info()  { :; }
}

@test "zfs_pool_owners_apply_mount: chown path owns the mount by numeric uid:gid" {
  _apply_env
  zfs_pool_owners_apply_mount tank0 /data/tank0 "" "alice" ""
  grep -q "1000:9000 ${MOUNT_ROOT}/data/tank0" "$CHOWN_LOG"
}

@test "zfs_pool_owners_apply_mount: chown path links ~/Disks/<pool> to the mount" {
  _apply_env
  zfs_pool_owners_apply_mount tank0 /data/tank0 "" "alice" ""
  local link="${MOUNT_ROOT}/home/alice/Disks/tank0"
  [ -L "$link" ]
  [ "$(readlink "$link")" = "/data/tank0" ]
  grep -q "1000:9000 ${link}" "$CHOWN_LOG"   # symlink owned by numeric ids
}

@test "zfs_pool_owners_apply_mount: userless host leaves the mount root-owned" {
  _apply_env
  zfs_pool_owners_apply_mount tank0 /data/tank0 "" "" ""
  [ ! -s "$CHOWN_LOG" ]
  [ ! -e "${MOUNT_ROOT}/home/alice/Disks/tank0" ]
}

@test "zfs_pool_owners_apply_mount: a declared user absent from the installed passwd is skipped" {
  _apply_env
  zfs_pool_owners_apply_mount tank0 /data/tank0 "" "zara" ""
  [ ! -s "$CHOWN_LOG" ]
  [ ! -e "${MOUNT_ROOT}/home/zara/Disks/tank0" ]
}

@test "zfs_pool_owners_apply_mount: acl path setfacls numeric entries + links users" {
  _apply_env
  SETFACL_LOG="$BATS_TEST_TMPDIR/setfacl.log"; : > "$SETFACL_LOG"
  setfacl() { printf '%s\n' "$*" >> "$SETFACL_LOG"; }
  zfs_pool_owners_apply_mount tank0 /data/tank0 "alice bob" "alice bob" ""
  grep -q "1000:9000 ${MOUNT_ROOT}/data/tank0" "$CHOWN_LOG"  # base owner
  grep -q "u:1000:rwx" "$SETFACL_LOG"
  grep -q "u:1001:rwx" "$SETFACL_LOG"
  grep -q "m::rwx" "$SETFACL_LOG"
  [ -L "${MOUNT_ROOT}/home/alice/Disks/tank0" ]
  [ -L "${MOUNT_ROOT}/home/bob/Disks/tank0" ]
}

@test "zfs_pool_owners_apply_mount: acl @group becomes a numeric g:<gid> grant" {
  _apply_env
  SETFACL_LOG="$BATS_TEST_TMPDIR/setfacl.log"; : > "$SETFACL_LOG"
  setfacl() { printf '%s\n' "$*" >> "$SETFACL_LOG"; }
  zfs_pool_owners_apply_mount tank0 /data/tank0 "alice @family" \
    "alice bob carol" "family:bob,carol"
  grep -q "g:1500:rwx" "$SETFACL_LOG"
}

@test "zfs_pool_owners_apply_mount: @group members each get a symlink" {
  _apply_env
  zfs_pool_owners_apply_mount tank0 /data/tank0 "alice @family" \
    "alice bob carol" "family:bob,carol"
  [ -L "${MOUNT_ROOT}/home/bob/Disks/tank0" ]
  [ -L "${MOUNT_ROOT}/home/carol/Disks/tank0" ]
}

# ── leftover-pool predicate (regression: single-mode unbound variable) ───────
# zfs_pool_owners_apply checks for an interactively-folded leftover OS-disk pool via
# the layout-MULTI associative arrays. In single-disk mode those arrays are
# never declared, so a bare `[[ -v arr[_leftover] ]]` arithmetic-evaluated the
# subscript and crashed the whole install under `set -u`
# ("_leftover: unbound variable"). The predicate must be safe when absent.

# The predicate now lives in the layout record interface (layout_has_leftover,
# lib/layout/state.sh); pool-owners.sh sources it transitively. The record
# backing is still _LAYOUT_IMPL_STORAGE_PARTS, so these fixtures drive
# the accessor.
@test "leftover predicate: defined and safe in single mode (undeclared arrays)" {
  run bash -uc "source '$BATS_TEST_DIRNAME/../../lib/zfs/pool-owners.sh'
    declare -F layout_has_leftover >/dev/null || { echo NO_FN; exit 3; }
    if layout_has_leftover; then echo HASLEFT; else echo NOLEFT; fi"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOLEFT"* ]]
  [[ "$output" != *"unbound variable"* ]]
  [[ "$output" != *"NO_FN"* ]]
}

@test "leftover predicate: true when a _leftover storage part exists" {
  run bash -uc "source '$BATS_TEST_DIRNAME/../../lib/zfs/pool-owners.sh'
    declare -gA _LAYOUT_IMPL_STORAGE_PARTS=([_leftover]='/dev/sdb1')
    if layout_has_leftover; then echo HASLEFT; else echo NOLEFT; fi"
  [ "$status" -eq 0 ]
  [[ "$output" == *"HASLEFT"* ]]
}

@test "leftover predicate: false when the array lacks a _leftover key" {
  run bash -uc "source '$BATS_TEST_DIRNAME/../../lib/zfs/pool-owners.sh'
    declare -gA _LAYOUT_IMPL_STORAGE_PARTS=([tank0]='/dev/sdc1')
    if layout_has_leftover; then echo HASLEFT; else echo NOLEFT; fi"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOLEFT"* ]]
}

@test "zfs_pool_owners_mode survives 03-install's ERR trap in a substitution" {
  # 03-install runs `set -E` with an exiting ERR trap; a counter `((n++))`
  # from 0 inside $(…) used to fire it and abort the ownership step.
  local script="$BATS_TEST_TMPDIR/owners.sh"
  cat >"$script" <<SCRIPT
set -Eeuo pipefail
trap 'exit 1' ERR
source "$BATS_TEST_DIRNAME/../../lib/zfs/pool-owners.sh"
mode="\$(zfs_pool_owners_mode "alice" "alice")"
echo "mode=\$mode"
SCRIPT
  run bash "$script"
  [ "$status" -eq 0 ]
  [ "$output" = "mode=chown" ]
}
