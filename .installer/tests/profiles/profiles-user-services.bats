#!/usr/bin/env bats
# Tests for the user-profile user_services enable (unified-host-profile/06).
# A user profile's user_services[] is enabled (systemctl --user enable's
# offline equivalent — a symlink into default.target.wants) after the user's
# programs + dotfiles are placed; a unit that isn't installed aborts with an
# actionable message (vs. the per-program list, which skips).

setup() {
  TEST_DIR="$(mktemp -d)"
  export MOUNT_ROOT="$TEST_DIR/mnt"
  mkdir -p "$MOUNT_ROOT"

  info()  { :; }
  warn()  { :; }
  error() { echo "[error] $*" >&2; exit 1; }
  export -f info warn error

  # shellcheck source=../../lib/profiles/runner.sh
  source "$BATS_TEST_DIRNAME/../../lib/profiles/runner.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "_profiles_resolve_user_unit: finds a present unit" {
  mkdir -p "$MOUNT_ROOT/usr/lib/systemd/user"
  : > "$MOUNT_ROOT/usr/lib/systemd/user/foo.service"
  run _profiles_resolve_user_unit foo "$MOUNT_ROOT/usr/lib/systemd/user"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/foo.service" ]]
}

@test "_profiles_resolve_user_unit: returns 1 when absent" {
  mkdir -p "$MOUNT_ROOT/usr/lib/systemd/user"
  run _profiles_resolve_user_unit ghost "$MOUNT_ROOT/usr/lib/systemd/user"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "enable_profile_user_services: enables a present user unit" {
  mkdir -p "$MOUNT_ROOT/usr/lib/systemd/user"
  : > "$MOUNT_ROOT/usr/lib/systemd/user/foo.service"
  arch-chroot() { echo "arch-chroot $*" >> "$TEST_DIR/chroot.log"; }

  run _profiles_enable_profile_user_services alice '{"user_services":["foo"]}'
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/chroot.log" ]
}

@test "enable_profile_user_services: aborts on a missing unit, naming it" {
  mkdir -p "$MOUNT_ROOT/usr/lib/systemd/user"
  arch-chroot() { :; }

  run _profiles_enable_profile_user_services alice \
    '{"user_services":["ghost"]}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"ghost"* ]]
}

@test "enable_profile_user_services: no user_services is a no-op" {
  arch-chroot() { echo called >> "$TEST_DIR/chroot.log"; }
  run _profiles_enable_profile_user_services alice '{"programs":["neovim"]}'
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_DIR/chroot.log" ]
}
