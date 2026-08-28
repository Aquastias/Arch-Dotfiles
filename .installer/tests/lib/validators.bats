#!/usr/bin/env bats
# Tests for tests/lib/validators.bash — the shared validator harness (ADR
# 0048, issue 01). The harness runs a generated artifact through a real
# validator binary, isolating each unit so sibling units in the same output
# dir cannot pollute the verdict, and SKIPs (never fails) when the binary is
# absent so the suite stays green on a minimal host.

setup() {
  load validators
  TEST_DIR="$(mktemp -d)"
}
teardown() { rm -rf "$TEST_DIR"; }

# A well-formed bind .mount whose Where= is /etc/ssh. Whether it is "good" or
# "bad" is decided purely by the file NAME the caller writes it to:
# etc-ssh.mount matches Where= (valid); persist-etc-ssh.mount does not (the
# historical persist-<esc>.mount bug). The content is identical either way.
_ssh_mount_unit() {  # $1 = destination path
  cat > "$1" <<'U'
[Unit]
Description=ssh bind
[Mount]
What=/persist/etc/ssh
Where=/etc/ssh
Type=none
Options=bind
[Install]
RequiredBy=local-fs.target
U
}

# ── validators_have ──────────────────────────────────────────────────────────

@test "validators_have: true for a present binary" {
  run validators_have systemd-analyze
  [ "$status" -eq 0 ]
}

@test "validators_have: false for an absent binary" {
  run validators_have definitely-not-a-real-binary-xyz
  [ "$status" -ne 0 ]
}

# ── validators_skip_unless ───────────────────────────────────────────────────

@test "skip_unless: an absent binary skips (never fails) the test" {
  # If `skip` fires, the `false` below never runs and bats reports this test
  # as skipped — the audit.sh "SKIPs never fail the run" contract.
  validators_skip_unless definitely-not-a-real-binary-xyz
  false
}

# ── validators_verify_unit ───────────────────────────────────────────────────

@test "verify_unit: a well-formed mount unit passes" {
  validators_skip_unless systemd-analyze
  _ssh_mount_unit "$TEST_DIR/etc-ssh.mount"
  run validators_verify_unit "$TEST_DIR/etc-ssh.mount"
  [ "$status" -eq 0 ]
}

@test "verify_unit: Where≠name is rejected" {
  validators_skip_unless systemd-analyze
  _ssh_mount_unit "$TEST_DIR/persist-etc-ssh.mount"
  run validators_verify_unit "$TEST_DIR/persist-etc-ssh.mount"
  [ "$status" -ne 0 ]
  [[ "$output" =~ [Ww]here ]]
}

@test "verify_unit: isolates the unit from a bad sibling in the same dir" {
  # systemd-analyze verify loads every unit in the file's directory; the
  # harness must copy the target into a fresh dir so a broken sibling cannot
  # flip a good unit's verdict.
  validators_skip_unless systemd-analyze
  _ssh_mount_unit "$TEST_DIR/etc-ssh.mount"
  _ssh_mount_unit "$TEST_DIR/persist-etc-ssh.mount"
  run validators_verify_unit "$TEST_DIR/etc-ssh.mount"
  [ "$status" -eq 0 ]
}
