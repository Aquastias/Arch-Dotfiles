#!/usr/bin/env bats
# Tests for lib/chroot/password.sh — applies the FINAL root password from
# ROOT_PW. The Host-Secret-over-collected precedence is resolved host-side
# (chroot.sh:_resolve_root_password, covered in chroot-configure.bats), so this
# script has a single channel: whatever ROOT_PW carries is what root gets.

setup() {
  TEST_DIR="$(mktemp -d)"
  mkdir -p "$TEST_DIR/bin"

  # sed: no-op (sudoers modification not under test)
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_DIR/bin/sed"
  # chpasswd: capture stdin
  printf '#!/usr/bin/env bash\ncat > "%s/chpasswd_input"\n' "$TEST_DIR" \
    > "$TEST_DIR/bin/chpasswd"

  chmod +x "$TEST_DIR/bin"/*
  export PATH="$TEST_DIR/bin:$PATH"
}

teardown() { rm -rf "$TEST_DIR"; }

# ── applies the single resolved value in ROOT_PW ──────────────────────────────

@test "applies the ROOT_PW value to root via chpasswd" {
  run env ROOT_PW="envpassword" \
    bash "$BATS_TEST_DIRNAME/../../lib/chroot/password.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/chpasswd_input")" = "root:envpassword" ]
}
