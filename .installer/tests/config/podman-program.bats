#!/usr/bin/env bats
# virtualization/podman program — rootless subordinate ID ranges. Runs the
# install.sh with the package/sudo steps stubbed and the subid files seamed.

setup() {
  INSTALL="$BATS_TEST_DIRNAME/../../programs/virtualization/podman/install.sh"
  export PODMAN_SUBUID_FILE="$BATS_TEST_TMPDIR/subuid"
  export PODMAN_SUBGID_FILE="$BATS_TEST_TMPDIR/subgid"
  LOG="$BATS_TEST_TMPDIR/calls"; : >"$LOG"; export LOG
  STUBS="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUBS"
  printf '#!/usr/bin/env bash\necho "usermod $*" >>"$LOG"\n' >"$STUBS/usermod"
  printf '#!/usr/bin/env bash\n"$@"\n' >"$STUBS/sudo"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$STUBS/fakehelper"
  chmod +x "$STUBS"/*
}

# _run_for <user> — the install as <user> (print_status stubbed).
_run_for() {
  run env PATH="$STUBS:$PATH" USER="$1" AUR_HELPER=fakehelper bash -c \
    'print_status() { :; }; source "$0"' "$INSTALL"
}

@test "first podman user gets 100000-165535" {
  : >"$PODMAN_SUBUID_FILE"; : >"$PODMAN_SUBGID_FILE"
  _run_for alice
  [ "$status" -eq 0 ]
  grep -qx "usermod --add-subuids 100000-165535 alice" "$LOG"
  grep -qx "usermod --add-subgids 100000-165535 alice" "$LOG"
}

@test "a second user gets the next free range, never an overlap" {
  # Every user got 100000-165535, so two podman users shared their IDs.
  echo "alice:100000:65536" >"$PODMAN_SUBUID_FILE"
  echo "alice:100000:65536" >"$PODMAN_SUBGID_FILE"
  _run_for bob
  [ "$status" -eq 0 ]
  grep -qx "usermod --add-subuids 165536-231071 bob" "$LOG"
  grep -qx "usermod --add-subgids 165536-231071 bob" "$LOG"
}

@test "a user who already has a range is left alone" {
  echo "bob:300000:65536" >"$PODMAN_SUBUID_FILE"
  echo "bob:300000:65536" >"$PODMAN_SUBGID_FILE"
  _run_for bob
  [ "$status" -eq 0 ]
  ! grep -q usermod "$LOG"
}
