#!/usr/bin/env bats
# Tests for .os/lib/pool-owners.sh — the Owners Resolver (pure, ADR 0031).
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
  # shellcheck source=../lib/pool-owners.sh
  source "$BATS_TEST_DIRNAME/../lib/pool-owners.sh"
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

# ── pool_owners_apply_mount (thin I/O) ───────────────────────────────────────
# chown/chmod are stubbed (they need root); ln/mkdir run for real in a temp
# tree so the ~/Disks symlink behaviour is observable.

_apply_env() {
  MOUNT_ROOT="$BATS_TEST_TMPDIR/mnt"
  POOL_OWNERS_HOME_BASE="/home"
  CHOWN_LOG="$BATS_TEST_TMPDIR/chown.log"
  : > "$CHOWN_LOG"
  mkdir -p "${MOUNT_ROOT}/data/tank0" "${MOUNT_ROOT}/home/alice"
  chown() { printf '%s\n' "$*" >> "$CHOWN_LOG"; }
  chmod() { :; }
  warn()  { :; }
  info()  { :; }
}

@test "pool_owners_apply_mount: chown path owns the mount by the base user" {
  _apply_env
  pool_owners_apply_mount tank0 /data/tank0 "" "alice" ""
  grep -q "alice:alice ${MOUNT_ROOT}/data/tank0" "$CHOWN_LOG"
}

@test "pool_owners_apply_mount: chown path links ~/Disks/<pool> to the mount" {
  _apply_env
  pool_owners_apply_mount tank0 /data/tank0 "" "alice" ""
  local link="${MOUNT_ROOT}/home/alice/Disks/tank0"
  [ -L "$link" ]
  [ "$(readlink "$link")" = "/data/tank0" ]
}

@test "pool_owners_apply_mount: userless host leaves the mount root-owned" {
  _apply_env
  pool_owners_apply_mount tank0 /data/tank0 "" "" ""
  [ ! -s "$CHOWN_LOG" ]
  [ ! -e "${MOUNT_ROOT}/home/alice/Disks/tank0" ]
}

@test "pool_owners_apply_mount: acl path setfacls entries + links each user" {
  _apply_env
  mkdir -p "${MOUNT_ROOT}/home/bob"
  SETFACL_LOG="$BATS_TEST_TMPDIR/setfacl.log"; : > "$SETFACL_LOG"
  setfacl() { printf '%s\n' "$*" >> "$SETFACL_LOG"; }
  pool_owners_apply_mount tank0 /data/tank0 "alice bob" "alice bob" ""
  grep -q "alice:alice ${MOUNT_ROOT}/data/tank0" "$CHOWN_LOG"  # base owner
  grep -q "u:alice:rwx" "$SETFACL_LOG"
  grep -q "u:bob:rwx" "$SETFACL_LOG"
  grep -q "m::rwx" "$SETFACL_LOG"
  [ -L "${MOUNT_ROOT}/home/alice/Disks/tank0" ]
  [ -L "${MOUNT_ROOT}/home/bob/Disks/tank0" ]
}

@test "pool_owners_apply_mount: @group members each get a symlink" {
  _apply_env
  mkdir -p "${MOUNT_ROOT}/home/bob" "${MOUNT_ROOT}/home/carol"
  setfacl() { :; }
  pool_owners_apply_mount tank0 /data/tank0 "alice @family" \
    "alice bob carol" "family:bob,carol"
  [ -L "${MOUNT_ROOT}/home/bob/Disks/tank0" ]
  [ -L "${MOUNT_ROOT}/home/carol/Disks/tank0" ]
}
