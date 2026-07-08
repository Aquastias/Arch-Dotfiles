# Combination Matrix — two-tier install-combination testing

Status: ready-for-agent

Decision of record: **ADR 0046** (combination-matrix two-tier install testing),
building on ADR 0035 (profile-driven VM Harness), 0036 (unified profile /
Effective Config), 0039 (Guided Installer), 0040 + 0043 (Filesystem Adapter
axis + per-group filesystem), 0042 (persistent-fzf controller), 0044 (btrfs
impermanence rollback), 0045 (unified swap).

Glossary touched (`CONTEXT.md`, already updated): **Combination Matrix** (new),
**Console Answerer** (new); references Guided Installer, Effective Config, VM
Profile, VM Harness, Filesystem Adapter, Impermanence, Rollback Datasets.

## Problem Statement

When I install Arch with this installer, I want to trust that *no combination I
can pick from the menu* produces an error — not just the handful of scenarios I
happened to hand-author a VM profile for. Today ~40 curated `tests/vm/profiles/`
cover named cases (single, mirror, btrfs, impermanence, guided…), but the menu's
choice-space is effectively infinite and the curated set leaves most
combinations — especially mixed-filesystem and encrypted ones — untested. My
historically bug-dense areas (per-group filesystem, encrypted multi-disk,
xfs-root modprobe ordering, btrfs subvol rollback) were each found by luck or by
one bespoke profile. I want the coverage to be *systematic* and to *stay* honest
as the menu grows, without burning hundreds of VM-hours.

## Solution

A **Combination Matrix**: the generated space of menu-reachable install
combinations, checked in two tiers so cost matches the failure class.

- **Tier 1 (no VM, always-on):** for the *exhaustive* storage cluster (root
  filesystem × encryption × impermanence × topology × disk-mode × per-group
  data-pool filesystem/encryption, including mixed-filesystem cells), assemble
  the Effective Config and run `validate_install_context`. Runs in the bats
  suite in seconds — the always-on guarantee that no menu-reachable combination
  assembles to garbage.
- **Tier 2 (VM, on-demand):** a **pairwise (2-wise)** cover over the
  install-affecting axes, plus a pinned seed list of historically-broken
  tuples, actually installed and booted in a real VM through the config seam.

Axes, values, and exclusions are **derived from the menu's own option
functions** (`_ctl_topologies_for_fs`, `menu_rows`, picker/validation), never a
hand-kept spec — so the matrix can't drift from what the menu offers or emit an
impossible cell. Encrypted cells are **fully boot-verified** by a new **Console
Answerer** that types the real passphrase over serial. Staying in sync is
*enforced*: an axis-registry completeness assertion hard-fails the generator on
an unclassified new menu field, and CI diffs the committed coverage records.

## User Stories

1. As an installer author, I want every menu-reachable storage combination
   assembled and validated on every test run, so that "the menu let me pick
   something that won't assemble" is impossible to ship.
2. As an installer author, I want a pairwise subset of install-affecting
   combinations actually installed and booted in a VM, so that back-end/storage
   bugs that only surface on real hardware are caught systematically.
3. As an installer author, I want the matrix's axes and values derived from the
   menu's own functions, so that adding a filesystem or topology automatically
   expands coverage with no separate spec to maintain.
4. As an installer author, I want the generator to be structurally incapable of
   emitting an impossible cell (ext4+impermanence, raidz1+btrfs, mirror+1-disk),
   so that I never waste a VM on a combination the menu can't produce.
5. As an installer author, I want mixed-filesystem cells (zfs root + btrfs/ext4/
   xfs data pool, ext4 root + zfs data pool) as first-class matrix cells, so
   that my most bug-dense area is covered by construction.
6. As an installer author, I want per-group encryption crossed with per-group
   filesystem, so that "root encrypted, pool plaintext" and its inverses are
   exercised.
7. As an installer author, I want the historically-broken tuples pinned as
   mandatory cells (zfs-root+btrfs-pool, ext4-root+zfs-pool, btrfs-raid1-
   encrypted-multi, xfs-root, zfs-keyfile-on-root+encrypted-pool), so that known
   regressions can never silently return.
8. As an installer author, I want the pairwise draw seeded and deterministic, so
   that a failing cell-id always reproduces the same cell.
9. As an installer author, I want Tier 2 to install the exact Effective Config
   Tier 1 assembled (via the config seam), so that one assembler feeds both
   tiers and the back-end sees identical bytes to a menu-driven install.
10. As an installer author, I want the interactive Guided runtime covered by the
    existing fixed `--guided` smoke profiles rather than matrixed, since it is
    combination-independent.
11. As an installer author, I want every unencrypted cell boot-verified to its
    first-boot sentinel, so that an install that can't boot counts as a failure.
12. As an installer author, I want impermanent cells to run the `verify.rollback`
    two-boot proof (ephemeral wiped, persistent survived), so that impermanence
    is proven to actually work, not just install.
13. As an installer author, I want encrypted cells fully boot-verified by typing
    the real passphrase at the real prompt, so that encrypted installs are tested
    as close to reality as a human at the keyboard.
14. As an installer author, I want the Console Answerer to detect the LUKS/zfs
    prompt in the serial log and write the passphrase to the serial device, so
    that headless encrypted boot works without faking the unlock path.
15. As an installer author, I want GRUB cells to route their passphrase prompt to
    serial too (GRUB_CMDLINE parity with the existing systemd-boot injection), so
    that the Console Answerer works regardless of bootloader.
16. As an installer author, I want a hard `ENCRYPTED-BOOT-FAIL` result on a
    missed prompt rather than a 600 s hang, so that encrypted failures are fast
    and legible.
17. As an installer author, I want GPU as a full matrix axis {auto, amd, nvidia,
    intel} with an install-only oracle for non-auto vendors, so that real driver
    installs (not just `auto`→mesa) are exercised.
18. As an installer author, I want `nvidia × kernel` pinned as a pairwise pair,
    so that the DKMS-against-kernel-headers build is always covered.
19. As an installer author, I want the Tier-2 driver to never freeze my host:
    a preflight computes max parallelism from available RAM minus reserve and
    checks /dev/kvm, libvirtd, and free image-dir disk; a per-launch gate blocks
    until RAM frees rather than over-committing.
20. As an installer author, I want Tier 2 to default to 3-way parallel with a
    `--smoke` (pinned seeds only) / `--full` (whole pairwise) split, so that I
    can get quick confidence or full coverage on demand.
21. As an installer author, I want per-cell install timeouts in two bands (light
    ~45 min / heavy ~90 min, heavy = any desktop, nvidia, or AUR), so that a hung
    light cell fails fast while heavy cells don't false-fail.
22. As an installer author, I want the run to not fail-fast: all cells run,
    per-cell logs are kept, and a summary table prints PASS/FAIL/SKIP with a
    re-run hint per failure, so that I get the full picture each run.
23. As an installer author, I want encrypted-boot skips (if the Answerer is off)
    shown as SKIP not FAIL, so that skipped verification isn't mistaken for a
    regression.
24. As an installer author, I want to materialize any single cell to a runnable
    profile via `matrix.sh emit <cell-id>`, so that I can debug one failure in
    isolation with plain `vm.sh`.
25. As an installer author, I want the committed Matrix Manifest to record the
    Tier-2 set (cell-id + axes), so that exactly which combinations get a VM is
    reviewable and diffable.
26. As an installer author, I want a committed coverage-summary snapshot (axes →
    values → exclusions + per-tier counts), so that a silent constraint-model
    shrink (e.g. raidz2 dropped) shows as a one-line change + count delta.
27. As an installer author, I want CI to regenerate both records and diff them
    against the committed snapshots, so that any coverage change fails CI until
    consciously committed.
28. As an installer author, I want the generator to hard-fail on a new
    `_MENU_FIELDS` entry that isn't in the axis registry, so that adding a menu
    option forces me to classify it into the matrix before merge.
29. As an installer author who runs `/improve-codebase-architecture`, I want a
    behavior-preserving refactor to regenerate the matrix to a no-op and a
    menu-touching one to trip the assertion/diff, so that refactors keep the
    tests in sync automatically.
30. As an installer author, I want the sync contract documented under
    `docs/agents/`, so that menu-editing and refactor workflows know to run
    `matrix.sh gen` at wrap-up.
31. As an installer author, I want a tracer-bullet first slice — generator emits
    a 1-cell manifest → Tier-1 validates it → Tier-2 installs it end-to-end — so
    that the whole spine is proven before axes, the Answerer, and parallelism
    fan out.
32. As an installer author, I want resilience axes (`by_id`, `reorder_boot_
    disks`, `resilience`, `dirty_cache`) to stay on their curated profiles rather
    than matrixed, so that orthogonal robustness probes don't multiply flakiness.

## Implementation Decisions

**Two failure classes, two tiers, two oracles (ADR 0046).** A menu choice fails
either at *assembly* (cheapest oracle: `assemble` → `validate_install_context`
on the host, no VM) or at *install/boot* (only oracle: a real VM). Tier 1 is
exhaustive where axes interact (the storage cluster); Tier 2 is pairwise over
the install-affecting axes. Tier 2 reuses Tier 1's assembler and installs via
the config seam (`install.sh <config-file>`), not `--guided`.

**Entry point.** `.os/tools/matrix.sh` with subcommands `gen` / `emit <cell-id>`
/ `run [--smoke|--full]`, mirroring `vm.sh`. Generator logic lives in small
sourced lib helpers (see modules) so it is unit-testable without the driver.

**Deep modules to build:**

- **Axis Registry** — pure map from every `_MENU_FIELDS` path to a role
  (`storage-cluster` / `scalar-sweep` / `pairwise-affecting` / `inert`) and a
  light/heavy weight. Public: return the role/weight for a path; assert the
  registry covers `_MENU_FIELDS` *exactly* (hard-fail `unclassified axis <path>`
  on a gap). The stay-in-sync enforcer.
- **Cell Generator + Constraint Model** — sources `lib/config/*` and
  `lib/guided-controller.sh`, walks the option functions, and emits the Tier-1
  exhaustive storage-cluster cells and the Tier-2 pairwise+seed cells as JSON
  lines (cell-id + axis assignment). Reachability comes from the menu functions,
  so impossible cells are structurally excluded. Seeds are unioned in
  unconditionally.
- **Pairwise Reducer** — pure covering-array builder: axes + values +
  constraints → deterministic (seeded) 2-wise cover. Independent of the menu.
- **Cell → Effective Config adapter** — maps a cell's axis assignment onto a
  Guided Config State and runs the existing assembler to an Effective Config.
  Thin; reuses the Guided assembler and disk-assignment.
- **Cell → VM Profile synthesizer** — pure: cell → ephemeral VM Profile JSON —
  `hardware.disks` = Σ `disk_count` (via `skeleton_total_disks`) at 20 GiB each,
  `verify` block from the oracle table (first-boot / rollback / encrypted),
  `timeouts.install` from the light/heavy band. Written to tmpfs; never
  committed.
- **Host-Resource Guard** — pure decision function: (MemAvailable, host reserve,
  per-VM RAM=8 GiB, image-dir free disk, /dev/kvm, libvirtd) → `max_parallel` or
  a structured abort reason; plus the per-launch gate predicate (can another VM
  start now?).
- **Coverage Summary** — pure: resolved axes → values → exclusions + per-tier
  counts → a stable, diffable snapshot.
- **Console Answerer** (`vm/lib/console-answerer.sh`, a VM Harness component) —
  its pure core is a prompt-matcher: given serial text, return whether a
  disk-unlock prompt is present and which passphrase to send (patterns for the
  mkinitcpio `encrypt` hook, `systemd-cryptsetup`, and zfs-native `load-key`).
  The IO shell watches the serial log and writes the known test passphrase to
  the serial char device (not `virsh send-key` — with `console=ttyS0` the prompt
  reads from `/dev/console`), with bounded retries → `ENCRYPTED-BOOT-FAIL`.

**Modules to modify:**

- **VM seed generator** — add a GRUB serial-console cmdline injection
  (`GRUB_CMDLINE_LINUX` parity) alongside the existing systemd-boot loader-entry
  injection, so encrypted GRUB cells route their prompt to serial.
- **Tier-2 driver** (`matrix.sh run`) — orchestration: host-resource guard,
  3-way parallel scheduling, oracle dispatch per cell, run-all collection, and
  the summary table + non-zero exit on any FAIL.
- **`docs/agents/`** — document the "menu-derived, CI-enforced" sync contract.
- **CI** — a job that runs `matrix.sh gen`, regenerates the coverage summary,
  and diffs both against the committed `.os/tests/vm/matrix-manifest.jsonl` and
  the coverage-summary snapshot.

**Oracle table (per cell).** plain → exit-0 + first-boot sentinel; impermanent →
exit-0 + `verify.rollback`; encrypted → its plain/impermanent peer's oracle,
unlocked by the Console Answerer. Encryption is not a boot-verify carve-out.

**Artifacts & scope of records.** Committed: `.os/tests/vm/matrix-manifest.jsonl`
(Tier-2 cells) + the coverage-summary snapshot. Not committed: Tier-1's
exhaustive list (regenerated live in bats) and all VM Profiles (materialized on
demand via `emit`). GPU is a full axis; `gpu≠auto` is install-only; `nvidia ×
kernel` is a pinned pair.

## Testing Decisions

**What makes a good test here:** assert external behavior of a module's
interface, not its internals. For the generator, that means asserting properties
of the *emitted cell set* (every value-pair covered, every pinned seed present,
zero impossible cells, deterministic output for a fixed seed) rather than how
the covering array is built. Feed known/mocked axis inputs and assert the JSON
output — the same style as the existing `menu.bats`, `guided-*.bats`, and
`profile-validate.bats`.

**Modules to unit-test (all pure deep modules; storage-critical trio is highest
priority):**

- **Pairwise Reducer** — every value-pair from the input axes appears in ≥1
  emitted row; constraint-excluded pairs never appear; identical output for a
  fixed seed (determinism); minimality is not asserted (implementation detail).
- **Axis Registry** — a field present in `_MENU_FIELDS` but absent from the
  registry hard-fails with its path; a fully-covered registry passes; role/weight
  lookups return the registered value. *(Storage-critical: the sync enforcer.)*
- **Cell Generator + Constraint Model** — no impossible cell is emitted (cross-
  check against `_validation_topology_for_fs` and the min-disk rules); every
  pinned seed is in the Tier-2 set; mixed-fs and per-group-encryption cells are
  present; the Tier-1 set equals the exhaustive storage-cluster cross-product
  under the exclusions. *(Storage-critical.)*
- **Cell → VM Profile synthesizer** — disk count = Σ disk_count for each
  topology; verify block matches the oracle table for plain/impermanent/
  encrypted; timeout matches the light/heavy band for representative cells.
- **Host-Resource Guard** — max_parallel math across representative
  (MemAvailable, reserve) inputs, clamped to the configured cap; abort reasons
  for missing /dev/kvm, libvirtd down, and insufficient disk; per-launch gate
  returns block/allow correctly.
- **Console Answerer prompt-matcher** — given captured serial text for each
  prompt variant (encrypt hook / systemd-cryptsetup / zfs-native), returns
  detected=true and the right passphrase; non-prompt serial noise returns
  detected=false.
- **Coverage Summary** — counts match the generated sets; output is stable
  across runs for identical inputs (diff-friendly).

**Tier-1 assembly bats** (`.os/tests/config/matrix-assembly.bats`) — iterates the
freshly generated Tier-1 cells, assembles each, and asserts a clean
`validate_install_context`. This is the always-on coverage job; prior art is
`install-print-config.bats` + `guided-emit.bats`.

**Integration / VM (not deeply unit-tested):** the Tier-2 driver process
orchestration and the Console Answerer's serial-write side are exercised via the
tracer-bullet VM run and existing harness bats (`vm-cli.bats`,
`sentinel-watcher.bats`), not pure unit tests.

## Out of Scope

- Matrixing the interactive Guided runtime (fzf render, in-guest picker) — it is
  combination-independent; the existing fixed `--guided` smoke profiles cover it.
- Resilience axes (`by_id`, `reorder_boot_disks`, `resilience`, `dirty_cache`) —
  they stay on their curated profiles.
- Functional GPU verification — virtual GPUs can't exercise a driver; `gpu≠auto`
  is install-only.
- 3-wise (or higher) interaction strength — Tier 2 is 2-wise; Tier 1's exhaustive
  storage cluster backstops higher-order assembly cases.
- Running Tier 2 in ordinary CI — it needs libvirt+KVM and is on-demand/local.
- Real-disk size realism — 20 GiB virtual disks; topology/count is what matters.

## Further Notes

- The Console Answerer is a distinct build slice with its own fragility budget
  (prompt-pattern drift, serial timing, GRUB parity). It closes the recorded
  encrypted headless-verify reboot-loop finding.
- The two committed records serve different jobs: the manifest is for *repro/
  pinning* of expensive VM cells; the coverage summary is the *drift guard* for
  the constraint model (a shrink Tier-1 bats alone would not catch, since it
  still passes with fewer valid cells).
- Slicing (for `/to-issues`): (1) tracer-bullet spine (1-cell manifest → Tier-1
  validate → Tier-2 install); (2) axis registry + completeness assertion; (3)
  pairwise reducer; (4) full cell generator + constraint model + mixed-fs +
  seeds; (5) VM-profile synthesizer + oracle dispatch; (6) host-resource guard +
  parallel driver + summary; (7) Console Answerer + GRUB serial parity +
  encrypted boot-verify; (8) coverage summary + manifest + CI diff + docs.
