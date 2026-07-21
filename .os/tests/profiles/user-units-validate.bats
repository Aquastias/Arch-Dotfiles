#!/usr/bin/env bats
# Validator-tier tests for the REAL shipped user service units (ADR 0048, issue
# 05): every programs/*/services/*.service the installer resolves and symlinks
# is run through real `systemd-analyze verify --user`, tolerating only the
# environmental "ExecStart binary not installed on the dev host" complaint (see
# validators_verify_user_unit). This catches malformed units — unknown keys, bad
# settings, broken sections — before they reach a booted system.
#
# The units are discovered dynamically, so a newly-added program's service unit
# is covered automatically. The existing profiles-user-services.bats keeps
# covering the resolver/enable logic; this validates the unit CONTENT.
#
# NOTE (issue 05 scope): the systemd-boot loader-entry emitter
# (lib/chroot/bootloader-systemd-boot.sh) has no unprivileged seam — it is a
# chroot script writing hardcoded /boot/efi paths — so its output is validated
# in the VM smoke tier (issue 06), not here. See the issue for the rationale.

setup() {
  load ../lib/validators
  OS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TEST_DIR="$(mktemp -d)"
}
teardown() { rm -rf "$TEST_DIR"; }

@test "every shipped user .service passes structural verify --user" {
  validators_skip_unless systemd-analyze
  local u found=0
  while IFS= read -r u; do
    found=1
    run validators_verify_user_unit "$u"
    if [ "$status" -ne 0 ]; then
      echo "verify failed for $u:"; echo "$output"; return 1
    fi
  done < <(find "$OS_DIR/programs" -name '*.service')
  [ "$found" -eq 1 ]   # guard: the glob actually matched units
}

@test "regression: a unit with an unknown directive is rejected" {
  validators_skip_unless systemd-analyze
  # Start from a real shipped unit so only the injected fault differs.
  local src; src="$(find "$OS_DIR/programs" -name '*.service' | head -1)"
  cp "$src" "$TEST_DIR/bad.service"
  printf '\n[Service]\nNotADirective=oops\n' >> "$TEST_DIR/bad.service"
  run validators_verify_user_unit "$TEST_DIR/bad.service"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "NotADirective" ]]
}
