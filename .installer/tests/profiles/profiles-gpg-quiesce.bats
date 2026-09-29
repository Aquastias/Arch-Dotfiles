#!/usr/bin/env bats
# Tests for _profiles_quiesce_gpg — stops a user's gpg daemons at the end of
# the chroot user phase. Regression: paru's key fetch starts keyboxd, which
# holds public-keys.d/pubring.db.lock stamped with the ISO hostname (archiso).
# gpg on the installed host can't prove that lock stale, so every later
# --recv-keys failed ("SQL library used incorrectly"). VM-found.

setup() {
  TEST_DIR="$(mktemp -d)"
  export MOUNT_ROOT="$TEST_DIR/mnt"
  export FAKE_HOME="$TEST_DIR/home/aquastias"
  export SU_LOG="$TEST_DIR/su.log"
  mkdir -p "$MOUNT_ROOT" "$FAKE_HOME"

  mkdir -p "$TEST_DIR/bin"
  PATH="$TEST_DIR/bin:$PATH"

  info()  { :; }
  warn()  { :; }
  error() { echo "[error] $*" >&2; exit 1; }
  export -f info warn error

  # Stub arch-chroot: drop the mount-root arg and run the chroot script here,
  # with getent resolving HOME into FAKE_HOME.
  cat > "$TEST_DIR/bin/arch-chroot" <<'STUB'
#!/usr/bin/env bash
shift  # drop the mount-root argument
getent() { printf 'u:x:1000:1000::%s:/bin/bash\n' "$FAKE_HOME"; }
export -f getent
exec "$@"
STUB
  # Stub su: record the user and command instead of switching user.
  cat > "$TEST_DIR/bin/su" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SU_LOG"
STUB
  chmod +x "$TEST_DIR/bin/arch-chroot" "$TEST_DIR/bin/su"

  # shellcheck source=../../lib/profiles/runner.sh
  source "$BATS_TEST_DIRNAME/../../lib/profiles/runner.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "kills the user's gpg daemons and sweeps install-time dotlocks" {
  local kd="$FAKE_HOME/.gnupg/public-keys.d"
  mkdir -p "$kd"
  : > "$kd/pubring.db"
  : > "$kd/pubring.db.lock"
  : > "$kd/.#lk0x00007fe068000c60.archiso.1470"
  run _profiles_quiesce_gpg aquastias
  [ "$status" -eq 0 ]
  grep -q '^- aquastias -c gpgconf --kill all$' "$SU_LOG"
  [ ! -e "$kd/pubring.db.lock" ]
  [ ! -e "$kd/.#lk0x00007fe068000c60.archiso.1470" ]
  [ -f "$kd/pubring.db" ]                    # the keyring itself stays
}

@test "no-op when the user never ran gpg" {
  run _profiles_quiesce_gpg aquastias
  [ "$status" -eq 0 ]
  [ ! -e "$SU_LOG" ]
}

@test "run_profiles quiesces gpg before revoking the temp sudo" {
  local R="$BATS_TEST_DIRNAME/../../lib/profiles/runner.sh"
  grep -A1 '_profiles_quiesce_gpg "\$u"' "$R" \
    | grep -q '_profiles_revoke_temp_sudo'
}
