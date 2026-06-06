Status: ready-for-human

# Dedup the two VM harnesses into a shared core

## Parent

`.scratch/lib-taxonomy-refactor/PRD.md` (split out of issue 07, whose
module relocation is done — commit f25aba6)

## What to build

Consolidate the shared code of the two **distinct** VM harnesses into a
single source of truth. They overlap heavily but serve different
purposes and have diverged:

- `.os/vm/_harness.sh` (~482 lines) — builds **persistent usable VMs**;
  sources `common.sh` + `packages/iso-resolver.sh`.
- `.os/tests/vm/_harness.sh` (~507 lines) — drives **automated tests**;
  also sources `tests/vm/lib/seed-generator.sh` +
  `tests/vm/lib/sentinel-watcher.sh` and does seed-ISO / sentinel /
  pool-verify.

Extract the common harness core into one shared file that both
harnesses `source`, keeping each entry harness's specific behaviour.
Behaviour-preserving for both.

## Acceptance criteria

- [ ] Common harness logic lives in one shared file; both harnesses
      source it (no copy-paste divergence)
- [ ] Persistent-VM harness (`vm/*.sh` entry scripts) behaviour unchanged
- [ ] Test harness (`testing-*.sh` entry scripts; seed + sentinel +
      verify) behaviour unchanged
- [ ] bats suite + `audit.sh` + `shellcheck.sh` stay green
      (917/0 · 82/82 · clean)
- [ ] **Human VM verification**: one real persistent `vm-*.sh` run and
      one `testing-*.sh` run, end-to-end on a libvirt/QEMU host

## Blocked by

- None — independent of Phase 2 (08/09).

Note: full verification needs a libvirt/QEMU host. The agent sandbox has
no libvirt, so an agent can only gate bats + shellcheck; a human must run
the two VM paths to confirm. Hence `ready-for-human`.
