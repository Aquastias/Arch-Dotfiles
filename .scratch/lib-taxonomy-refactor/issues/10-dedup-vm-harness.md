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

## Comments

Agent-side dedup implemented. Shared core extracted to
`.os/vm/_harness-core.sh`, sourced by both `vm/_harness.sh` and
`tests/vm/_harness.sh`:

- Identical functions moved to the core: `_ensure_libvirt_group`,
  `_ensure_libvirtd`, `_vm_exists`, `_vm_running`, `_vm_install_iso_path`,
  `_resolve_pinned_iso`.
- `_ensure_deps` parametrized as `_harness_ensure_deps "cmd:pkg"…` (common
  libvirt deps in the core; persistent adds `nc`+`python3`, test adds
  `script`).
- Divergent behaviour kept per-harness: seed generation, `_vm_create`
  flags, `_vm_destroy_undefine` strategy, `usage`/`_parse_args`
  (`--verify-boot`), `_vm_boot` log wording, console capture / installer
  launch, boot-verify, `run_harness` flow.

Static gates: bats 929/0, `audit.sh` 82/82, `shellcheck.sh` clean.
Source-smoke confirms both harnesses resolve every function via the core.

Still `ready-for-human`: the two end-to-end VM runs (one `vm-*.sh`, one
`testing-*.sh`) on a libvirt/QEMU host remain — the sandbox has no
libvirt.
