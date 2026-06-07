Status: done

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

Static gates: bats 931/0, `audit.sh` 82/82, `shellcheck.sh` clean.
Source-smoke confirms both harnesses resolve every function via the core.

### Human VM verification — DONE

Ran both paths end-to-end on a real libvirt/KVM host, serving the local
commits to the VMs via `git daemon` (changes weren't pushed):

- **Test harness** `testing-single-disk.sh --recreate` → `INSTALLER-EXIT-0`,
  harness exit 0.
- **Persistent harness** `vm-kde.sh` (run under throwaway name
  `arch-kde-verify` to avoid touching the real `arch-kde`) → installed
  KDE, rebooted, installed system stayed up. Exit 0. Confirms the
  persistent-specific path (HTTP server + `virsh send-key`).

Both exercise the shared core. The runs also re-validated issues 08/09 in
a real install (layout plan + ESP + pools correct).

Regression found + fixed during verification (commit
`fix(wipe): Tolerate a non-existent target disk in the prior-state
probe`): the install's resolved target set can name a disk absent on the
machine (the committed config's `os_pool.disks` lists another host's
NVMe disks); `_wipe_probe_disk` ran `lsblk`/`dd` on them and tripped the
ERR trap under `pipefail` (the pre-refactor `is_disk_zeroed` masked this
by being called inside an `if`). Now guarded with `[[ -b "$disk" ]]` so a
non-existent target is reported blank. Re-run confirmed 0 wipe errors.
