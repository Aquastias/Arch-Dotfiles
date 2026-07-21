Status: ready-for-agent

# Mount-unit validator + shared `validators.bash` harness

## Parent

`.scratch/installer-test-realism/PRD.md`

## What to build

The first vertical slice of the unprivileged validator tier (ADR 0048),
end to end: a shared bats harness plus the mount-unit validator that
proves it.

The harness (`tests/lib/validators.bash`) is the one new deep module: run
a named generator into a tmpdir, shell out to a validator binary, return
pass/fail, and `skip` (never fail) when the binary is absent — mirroring
`audit.sh` SKIP semantics so the suite stays green on a minimal host. It
encapsulates tmpdir setup, invocation, and the binary-presence check
behind a stable surface the later slices (03/04/05) reuse.

The validator: run the real `imp_write_mount_unit` generator and validate
the emitted `.mount` unit(s) with real `systemd-analyze verify`, asserting
on the naming / `Where=` correctness the `persist-<esc>.mount` bug
violated.

Then trim the overlap: delete the `$CALLS` / raw-string mount-unit
assertions in the existing impermanence tests the validator now covers for
real. Keep pure-logic assertions (path-escaping inputs, branch selection)
it does not exercise.

## Acceptance criteria

- [ ] `tests/lib/validators.bash` exists: generator-into-tmpdir + validator
      invocation + SKIP-when-binary-absent
- [ ] Harness has its own bats: SKIP-on-absent-binary, PASS on a valid
      artifact, FAIL on a broken one
- [ ] A bats file runs real `imp_write_mount_unit` output through
      `systemd-analyze verify`
- [ ] A regression asserts the escaped unit name matches `Where=` — fails
      on the historical `persist-<esc>.mount` bug, passes on its fix
- [ ] Overlapping `$CALLS`/raw mount-unit assertions removed from the
      impermanence tests; net stub count down
- [ ] `tests/run.sh` and `tests/shellcheck.sh` pass

## Blocked by

None - can start immediately (establishes the shared harness).
