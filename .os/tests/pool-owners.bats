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
