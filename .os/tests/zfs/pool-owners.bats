#!/usr/bin/env bats
# Tests for .os/lib/zfs/pool-owners.sh — the Owners Resolver (pure, ADR 0031).
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

# ── pool_owners_base ─────────────────────────────────────────────────────────

@test "pool_owners_base: omitted owners defaults to the Primary User" {
  run pool_owners_base "" "alice bob"
  [ "$status" -eq 0 ]
  [ "$output" = "alice" ]
}

@test "pool_owners_base: a single named user owns the pool" {
  run pool_owners_base "carol" "alice bob carol"
  [ "$status" -eq 0 ]
  [ "$output" = "carol" ]
}

@test "pool_owners_base: first listed user wins even after a @group" {
  run pool_owners_base "@family bob alice" "alice bob"
  [ "$status" -eq 0 ]
  [ "$output" = "bob" ]
}

# ── pool_owners_mode ─────────────────────────────────────────────────────────

@test "pool_owners_mode: omitted owners with a Primary User is a chown" {
  run pool_owners_mode "" "alice bob"
  [ "$status" -eq 0 ]
  [ "$output" = "chown" ]
}

@test "pool_owners_mode: omitted owners on a userless host stays root" {
  run pool_owners_mode "" ""
  [ "$status" -eq 0 ]
  [ "$output" = "root" ]
}

@test "pool_owners_mode: a single named user is a chown (no ACL)" {
  run pool_owners_mode "carol" "alice bob carol"
  [ "$status" -eq 0 ]
  [ "$output" = "chown" ]
}

@test "pool_owners_mode: more than one user needs ACLs" {
  run pool_owners_mode "alice bob" "alice bob"
  [ "$status" -eq 0 ]
  [ "$output" = "acl" ]
}

@test "pool_owners_mode: any @group needs ACLs" {
  run pool_owners_mode "alice @family" "alice" "family:alice,bob"
  [ "$status" -eq 0 ]
  [ "$output" = "acl" ]
}

# ── pool_owners_access_users (drives ~/Disks/<pool> symlinks) ─────────────────

@test "pool_owners_access_users: omitted owners is just the Primary User" {
  run pool_owners_access_users "" "alice bob"
  [ "$status" -eq 0 ]
  [ "$output" = "alice" ]
}

@test "pool_owners_access_users: userless host grants access to no one" {
  run pool_owners_access_users "" ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "pool_owners_access_users: a single named user gets the only symlink" {
  run pool_owners_access_users "carol" "alice bob carol"
  [ "$status" -eq 0 ]
  [ "$output" = "carol" ]
}

@test "pool_owners_access_users: union of listed users and @group members" {
  run pool_owners_access_users "alice @family" "alice bob carol" \
    "family:bob,carol"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "alice" ]
  [[ "$output" == *bob* ]]
  [[ "$output" == *carol* ]]
  [ "${#lines[@]}" -eq 3 ]
}

@test "pool_owners_access_users: a user in both list and @group appears once" {
  run pool_owners_access_users "alice @family" "alice bob" "family:alice,bob"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
}

# ── pool_owners_acl_entries (the setfacl plan for ACL pools) ─────────────────

@test "pool_owners_acl_entries: user gets an rwx entry + default mirror" {
  run pool_owners_acl_entries "alice bob"
  [ "$status" -eq 0 ]
  [[ "$output" == *"u:alice:rwx"* ]]
  [[ "$output" == *"u:bob:rwx"* ]]
  [[ "$output" == *"d:u:alice:rwx"* ]]
  [[ "$output" == *"d:u:bob:rwx"* ]]
}

@test "pool_owners_acl_entries: @group gets a group rwx entry + default mirror" {
  run pool_owners_acl_entries "@family"
  [ "$status" -eq 0 ]
  [[ "$output" == *"g:family:rwx"* ]]
  [[ "$output" == *"d:g:family:rwx"* ]]
}

@test "pool_owners_acl_entries: sets the ACL mask to rwx (incl. default)" {
  run pool_owners_acl_entries "alice @family"
  [ "$status" -eq 0 ]
  [[ "$output" == *"m::rwx"* ]]
  [[ "$output" == *"d:m::rwx"* ]]
}

# ── pool_owners_validate (drives layout_validate, ADR 0031) ──────────────────

@test "pool_owners_validate: omitted owners is always valid" {
  run pool_owners_validate "" "alice bob" ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "pool_owners_validate: a declared user is valid" {
  run pool_owners_validate "alice" "alice bob" ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "pool_owners_validate: an undeclared user fails with a reason" {
  run pool_owners_validate "carol" "alice bob" ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"carol"* ]]
}

@test "pool_owners_validate: a @group with members is valid" {
  run pool_owners_validate "alice @family" "alice bob" "family:alice,bob"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "pool_owners_validate: a @group with no members fails with a reason" {
  run pool_owners_validate "@family" "alice bob" ""
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

# ── pool_owners_apply_mount (thin I/O, host-side numeric translation) ─────────
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

@test "pool_owners_apply_mount: chown path owns the mount by numeric uid:gid" {
  _apply_env
  pool_owners_apply_mount tank0 /data/tank0 "" "alice" ""
  grep -q "1000:9000 ${MOUNT_ROOT}/data/tank0" "$CHOWN_LOG"
}

@test "pool_owners_apply_mount: chown path links ~/Disks/<pool> to the mount" {
  _apply_env
  pool_owners_apply_mount tank0 /data/tank0 "" "alice" ""
  local link="${MOUNT_ROOT}/home/alice/Disks/tank0"
  [ -L "$link" ]
  [ "$(readlink "$link")" = "/data/tank0" ]
  grep -q "1000:9000 ${link}" "$CHOWN_LOG"   # symlink owned by numeric ids
}

@test "pool_owners_apply_mount: userless host leaves the mount root-owned" {
  _apply_env
  pool_owners_apply_mount tank0 /data/tank0 "" "" ""
  [ ! -s "$CHOWN_LOG" ]
  [ ! -e "${MOUNT_ROOT}/home/alice/Disks/tank0" ]
}

@test "pool_owners_apply_mount: a declared user absent from the installed passwd is skipped" {
  _apply_env
  pool_owners_apply_mount tank0 /data/tank0 "" "zara" ""
  [ ! -s "$CHOWN_LOG" ]
  [ ! -e "${MOUNT_ROOT}/home/zara/Disks/tank0" ]
}

@test "pool_owners_apply_mount: acl path setfacls numeric entries + links users" {
  _apply_env
  SETFACL_LOG="$BATS_TEST_TMPDIR/setfacl.log"; : > "$SETFACL_LOG"
  setfacl() { printf '%s\n' "$*" >> "$SETFACL_LOG"; }
  pool_owners_apply_mount tank0 /data/tank0 "alice bob" "alice bob" ""
  grep -q "1000:9000 ${MOUNT_ROOT}/data/tank0" "$CHOWN_LOG"  # base owner
  grep -q "u:1000:rwx" "$SETFACL_LOG"
  grep -q "u:1001:rwx" "$SETFACL_LOG"
  grep -q "m::rwx" "$SETFACL_LOG"
  [ -L "${MOUNT_ROOT}/home/alice/Disks/tank0" ]
  [ -L "${MOUNT_ROOT}/home/bob/Disks/tank0" ]
}

@test "pool_owners_apply_mount: acl @group becomes a numeric g:<gid> grant" {
  _apply_env
  SETFACL_LOG="$BATS_TEST_TMPDIR/setfacl.log"; : > "$SETFACL_LOG"
  setfacl() { printf '%s\n' "$*" >> "$SETFACL_LOG"; }
  pool_owners_apply_mount tank0 /data/tank0 "alice @family" \
    "alice bob carol" "family:bob,carol"
  grep -q "g:1500:rwx" "$SETFACL_LOG"
}

@test "pool_owners_apply_mount: @group members each get a symlink" {
  _apply_env
  pool_owners_apply_mount tank0 /data/tank0 "alice @family" \
    "alice bob carol" "family:bob,carol"
  [ -L "${MOUNT_ROOT}/home/bob/Disks/tank0" ]
  [ -L "${MOUNT_ROOT}/home/carol/Disks/tank0" ]
}

# ── leftover-pool predicate (regression: single-mode unbound variable) ───────
# pool_owners_apply checks for an interactively-folded leftover OS-disk pool via
# the layout-MULTI associative arrays. In single-disk mode those arrays are
# never declared, so a bare `[[ -v arr[_leftover] ]]` arithmetic-evaluated the
# subscript and crashed the whole install under `set -u`
# ("_leftover: unbound variable"). The predicate must be safe when absent.

@test "leftover predicate: defined and safe in single mode (undeclared arrays)" {
  run bash -uc "source '$BATS_TEST_DIRNAME/../../lib/zfs/pool-owners.sh'
    declare -F _pool_owners_has_leftover >/dev/null || { echo NO_FN; exit 3; }
    if _pool_owners_has_leftover; then echo HASLEFT; else echo NOLEFT; fi"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOLEFT"* ]]
  [[ "$output" != *"unbound variable"* ]]
  [[ "$output" != *"NO_FN"* ]]
}

@test "leftover predicate: true when a _leftover storage part exists" {
  run bash -uc "source '$BATS_TEST_DIRNAME/../../lib/zfs/pool-owners.sh'
    declare -gA _LAYOUT_IMPL_STORAGE_PARTS=([_leftover]='/dev/sdb1')
    if _pool_owners_has_leftover; then echo HASLEFT; else echo NOLEFT; fi"
  [ "$status" -eq 0 ]
  [[ "$output" == *"HASLEFT"* ]]
}

@test "leftover predicate: false when the array lacks a _leftover key" {
  run bash -uc "source '$BATS_TEST_DIRNAME/../../lib/zfs/pool-owners.sh'
    declare -gA _LAYOUT_IMPL_STORAGE_PARTS=([tank0]='/dev/sdc1')
    if _pool_owners_has_leftover; then echo HASLEFT; else echo NOLEFT; fi"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOLEFT"* ]]
}
