# Persistent flow + shared core

Status: done

## Parent

`.scratch/vm-profile-harness/PRD.md`

## What to build

Stand up the persistent VM flow behind `vm.sh`, driven by a profile.
Refactor the existing persistent harness (`vm/_harness.sh` +
`_harness-core.sh`) into two modules under `vm/lib/`: a shared `core.sh`
(dependency checks, libvirt group/daemon ensure, ISO resolution, VM state
predicates, domain create/boot, storage-pool refresh, and fixture
staging) and `flow-persistent.sh` (spice graphics, HTTP run-script served
on the libvirt gateway, `send-key` console typing, wait-for-IP /
wait-for-SSH, wait-for-poweroff, reboot into the installed system).

`vm.sh` (no `--testing`) resolves + validates the profile (issue 01),
stages any `fixtures`, then runs the persistent flow. Behaviour matches
today's `vm-kde.sh` etc., but config now comes from the resolved profile
rather than an inlined `INSTALL_CONFIG_CONTENT`. Env-var overrides
(RAM, timeouts, ISO pin) still win over profile values; timeouts resolve
env > profile > flow default.

Fold the `VM_FIXTURE_FILES` staging hook into `core.sh`, and move +
rewire `vm-harness-fixtures.bats` to `tests/vm/` so it drives the
relocated staging function. Real-VM verification is deferred to issue 07;
this issue is verified by shellcheck, the dry-run, and bats.

## Acceptance criteria

- [ ] `vm.sh --profile <persistent-profile>` runs the full persistent
      flow path (no `--testing`).
- [ ] `core.sh` and `flow-persistent.sh` exist under `vm/lib/`;
      `_harness-core.sh` and `vm/_harness.sh` are removed (logic folded in).
- [ ] Fixture staging lives in `core.sh`; `vm-harness-fixtures.bats` moved
      to `tests/vm/` and rewired, still green.
- [ ] Env vars override profile hardware/timeouts; timeout precedence is
      env > profile > flow default.
- [ ] `--recreate` and `--help` behave as before.
- [ ] `tests/run.sh` and `tests/shellcheck.sh` are green (no real VM run
      required to merge).

## Blocked by

- `.scratch/vm-profile-harness/issues/01-profile-resolution-validation.md`
