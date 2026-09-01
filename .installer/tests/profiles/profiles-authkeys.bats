#!/usr/bin/env bats
# Tests for _profiles_write_authorized_keys — the SSH authorized_keys writer.
# Regression: it must NOT stage through ${MOUNT_ROOT}/tmp, since on a ZFS
# install /tmp is its own dataset (rpool/tmp) that mounts over the host's write.

setup() {
  TEST_DIR="$(mktemp -d)"
  export MOUNT_ROOT="$TEST_DIR/mnt"
  export FAKE_HOME="$TEST_DIR/home/aquastias"
  mkdir -p "$MOUNT_ROOT/tmp" "$FAKE_HOME"

  mkdir -p "$TEST_DIR/bin"
  PATH="$TEST_DIR/bin:$PATH"

  info()  { :; }
  warn()  { :; }
  error() { echo "[error] $*" >&2; exit 1; }
  export -f info warn error

  # Stub arch-chroot: drop the mount-root arg and run the chroot script here,
  # with getent resolving HOME into FAKE_HOME and chown a no-op (not root).
  cat > "$TEST_DIR/bin/arch-chroot" <<'STUB'
#!/usr/bin/env bash
shift  # drop the mount-root argument
getent() { printf 'u:x:1000:1000::%s:/bin/bash\n' "$FAKE_HOME"; }
export -f getent
exec "$@"
STUB
  chmod +x "$TEST_DIR/bin/arch-chroot"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_DIR/bin/chown"
  chmod +x "$TEST_DIR/bin/chown"

  # shellcheck source=../../lib/profiles/runner.sh
  source "$BATS_TEST_DIRNAME/../../lib/profiles/runner.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "writes each key and never stages a host /tmp file" {
  run _profiles_write_authorized_keys aquastias \
    '{"ssh_authorized_keys":["ssh-ed25519 AAAAONE a","ssh-ed25519 AAAATWO b"]}'
  [ "$status" -eq 0 ]
  [ -f "$FAKE_HOME/.ssh/authorized_keys" ]
  grep -q 'ssh-ed25519 AAAAONE a' "$FAKE_HOME/.ssh/authorized_keys"
  grep -q 'ssh-ed25519 AAAATWO b' "$FAKE_HOME/.ssh/authorized_keys"
  # The ZFS-dataset bug's trigger: no staging file under the host mount /tmp.
  [ ! -e "$MOUNT_ROOT/tmp/.authorized_keys_aquastias" ]
}

@test "no-op when the user has no keys" {
  run _profiles_write_authorized_keys aquastias '{"ssh_authorized_keys":[]}'
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_HOME/.ssh/authorized_keys" ]
}

@test ".ssh is created private (0700 dir, 0600 file)" {
  run _profiles_write_authorized_keys aquastias \
    '{"ssh_authorized_keys":["ssh-ed25519 AAAAKEY a"]}'
  [ "$status" -eq 0 ]
  [ "$(stat -c '%a' "$FAKE_HOME/.ssh")" = 700 ]
  [ "$(stat -c '%a' "$FAKE_HOME/.ssh/authorized_keys")" = 600 ]
}
