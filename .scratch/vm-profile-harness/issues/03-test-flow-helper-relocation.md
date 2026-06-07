# Test flow + helper relocation

Status: ready-for-agent

## Parent

`.scratch/vm-profile-harness/PRD.md`

## What to build

Add the disposable test flow behind `vm.sh --testing`, driven by a
profile. Refactor the existing test harness (`tests/vm/_harness.sh`) into
`vm/lib/flow-test.sh`, sharing `core.sh` from issue 02: headless
graphics, cloud-init `runcmd` seed, serial console capture, sentinel
watcher, installer exit-code propagation (0 / 124 timeout / 125
boot-fail), and opt-in boot-verify (eject cdroms, optional disk reorder,
dirty-cache injection, and pool-verify driven by the profile's `verify`
block — pools, mounts, by-id, owned).

Relocate the test-only helpers from `tests/vm/lib/` to `vm/lib/`:
`sentinel-watcher.sh`, `seed-generator.sh`, `vm-pool-verify.sh`, and
`reorder-disks.py`. Move their unit bats to `tests/vm/` and rewire every
source path (`seed-generator.bats` also sources `vm-pool-verify.sh`).
Move `vm-fixtures-regenerate.bats` to `tests/vm/` and fix its relative
path (the script it tests, `vm/fixtures/regenerate.sh`, does not move).
Remove `tests/vm/_harness.sh`.

`tests/vm/` is left holding only profiles, run artifacts (`*.log`,
`.vm-test/`), and the relocated bats. Real-VM verification is deferred to
issue 07; this issue is verified by shellcheck, the dry-run, and bats.

## Acceptance criteria

- [ ] `vm.sh --testing --profile <test-profile>` runs the full test flow
      path and propagates the installer exit code.
- [ ] `--verify-boot` drives boot-verify using the profile's `verify`
      block (pools/mounts/by-id/owned, reorder, dirty-cache).
- [ ] `flow-test.sh` exists under `vm/lib/`; `tests/vm/_harness.sh` is
      removed.
- [ ] `sentinel-watcher.sh`, `seed-generator.sh`, `vm-pool-verify.sh`,
      `reorder-disks.py` live under `vm/lib/`.
- [ ] Their bats (`sentinel-watcher`, `seed-generator`, `vm-pool-verify`,
      `vm-reorder-disks`) and `vm-fixtures-regenerate.bats` are under
      `tests/vm/`, rewired, and green.
- [ ] A test profile run WITHOUT `--testing` builds a persistent VM of
      that case (debug path).
- [ ] `tests/run.sh` and `tests/shellcheck.sh` are green (no real VM run
      required to merge).

## Blocked by

- `.scratch/vm-profile-harness/issues/01-profile-resolution-validation.md`
