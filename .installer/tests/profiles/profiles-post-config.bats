#!/usr/bin/env bats
# Tests for the Post-Config Hook (ADR 0160, amends ADR 0134): a user program
# may ship post-config.sh, run as its user after the Config Apply pass placed
# its home/ — for setup that needs the final config on disk (Doom's sync bakes
# its config dir's absolute path into the generated profile).

setup() {
  TEST_DIR="$(mktemp -d)"
  export MOUNT_ROOT="$TEST_DIR/mnt"
  export INSTALLER_DIR="$TEST_DIR/installer"

  info()  { echo "[info] $*"; }
  warn()  { :; }
  error() { echo "[error] $*" >&2; exit 1; }
  export -f info warn error

  # shellcheck source=../../lib/profiles/runner.sh
  source "$BATS_TEST_DIRNAME/../../lib/profiles/runner.sh"
  # shellcheck source=../../lib/config/program-registry.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/program-registry.sh"

  # with-hook ships post-config.sh; plain does not.
  local name runtime="$MOUNT_ROOT$_RUNNER_RUNTIME_DIR/programs/dev"
  for name in with-hook plain; do
    mkdir -p "$INSTALLER_DIR/programs/dev/$name" "$runtime/$name"
  done
  : > "$runtime/with-hook/post-config.sh"
  arch-chroot() { echo "arch-chroot $*" >> "$TEST_DIR/chroot.log"; }
}

teardown() { rm -rf "$TEST_DIR"; }

@test "runs the post-config.sh of each user program that ships one" {
  run runner_run_post_config alice '{"programs":["plain","with-hook"]}'
  [ "$status" -eq 0 ]
  [ "$(grep -c . "$TEST_DIR/chroot.log")" -eq 1 ]
  [[ "$output" == *"with-hook"* ]]
  [[ "$output" != *"plain"* ]]
}

@test "no program ships a hook: no chroot call" {
  run runner_run_post_config alice '{"programs":["plain"]}'
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_DIR/chroot.log" ]
}

@test "the Config Apply pass runs the hook after placing the config" {
  grep -q 'runner_run_post_config' \
    "$BATS_TEST_DIRNAME/../../lib/profiles/runner.sh"
  run awk '/runner_apply_user_config "\$user"/ { a = NR }
           /runner_run_post_config "\$user"/ { p = NR }
           END { exit !(a && p && a < p) }' \
    "$BATS_TEST_DIRNAME/../../lib/profiles/runner.sh"
  [ "$status" -eq 0 ]
}
