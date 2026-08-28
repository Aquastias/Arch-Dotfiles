#!/usr/bin/env bats
# Validator-tier tests for the REAL impermanence mount-unit generator
# (imp_write_mount_unit in lib/impermanence-common.sh), checked with the REAL
# `systemd-analyze verify` via the shared harness (ADR 0048, issue 01).
#
# This replaces the "grep the emitted file for Where=/Type=" shape assertions
# with systemd's own verdict: a .mount unit whose Where= does not match its
# escaped file name is refused (the historical persist-<esc>.mount bug). The
# generator is exercised directly — no full impermanence_apply, no stubs.

setup() {
  load ../lib/validators

  TEST_DIR="$(mktemp -d)"
  UNITS="$TEST_DIR/units"
  mkdir -p "$UNITS"

  export IMPERMANENCE_MOUNT=/persist
  export FILESYSTEM=zfs   # → After=zfs-mount.service (no btrfs rollback lookup)

  # shellcheck source=../../lib/impermanence-common.sh
  source "$BATS_TEST_DIRNAME/../../lib/impermanence-common.sh"
}
teardown() { rm -rf "$TEST_DIR"; }

# ── every curated target produces a unit systemd accepts ─────────────────────

@test "every curated file/dir generates a systemd-valid .mount unit" {
  validators_skip_unless systemd-analyze
  local target esc
  for target in "${CURATED_FILES[@]}" "${CURATED_DIRS[@]}"; do
    imp_write_mount_unit "$target" "$UNITS"
    esc="$(systemd-escape --path "$target")"
    run validators_verify_unit "$UNITS/$esc.mount"
    if [ "$status" -ne 0 ]; then
      echo "verify failed for $target:"; echo "$output"; return 1
    fi
  done
}

# A path that escapes to a non-trivial name (dots, dashes) still round-trips:
# systemd-escape is the only thing tying file name to Where=, so this is the
# exact seam the persist-<esc>.mount bug broke.
@test "a dotted path (/etc/tmpfiles.d) verifies clean" {
  validators_skip_unless systemd-analyze
  imp_write_mount_unit /etc/tmpfiles.d "$UNITS"
  local esc; esc="$(systemd-escape --path /etc/tmpfiles.d)"
  run validators_verify_unit "$UNITS/$esc.mount"
  [ "$status" -eq 0 ]
}

# ── regression: the validator actually catches a name↔Where mismatch ─────────
# Reproduce the historical failure mode (unit named persist-<esc>.mount while
# Where= is the bare target). If the generator ever regresses to a name that
# does not match Where=, systemd-analyze verify goes red — proving this tier
# guards the class, not just today's happy path.

@test "regression: a persist-<esc> misnamed unit is rejected" {
  validators_skip_unless systemd-analyze
  imp_write_mount_unit /etc/ssh "$UNITS"
  # Rename to the buggy scheme; contents (Where=/etc/ssh) unchanged.
  mv "$UNITS/etc-ssh.mount" "$UNITS/persist-etc-ssh.mount"
  run validators_verify_unit "$UNITS/persist-etc-ssh.mount"
  [ "$status" -ne 0 ]
  [[ "$output" =~ [Ww]here ]]
}
