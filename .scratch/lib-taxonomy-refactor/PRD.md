Status: ready-for-human

# PRD: Foldered lib/ Taxonomy and Pure-Function Deepening

## Problem Statement

`.os/lib/` is a flat directory of ~40 sibling files. Domain
relationships are encoded only in filename prefixes (`layout-*`,
`zfs-*`, `wipe-*`, `config*`), so understanding one concept — the
Layout Module, the Disk Wipe, the Config cluster — means scanning the
whole directory and reading prefixes. Three problems compound this:

- **No locality by domain.** Files that form one module sit next to
  unrelated files. A maintainer touching the Layout Module has no folder
  to open; they grep.
- **Orchestration and logic are fused in two places.** `02-wipe.sh`
  carries device-aware wipe logic inline rather than delegating to a
  module, and the Layout Module fuses planning (pure, decidable up
  front) with partition/pool execution (destructive, I/O-bound). The
  decision-making is not separately testable.
- **Test-only modules live in `lib/`.** `vm-pool-verify.sh`,
  `seed-generator.sh`, and `sentinel-watcher.sh` are test infrastructure
  shipped alongside install-time code, blurring what the installer
  actually sources.

The flat layout also makes the codebase harder for an AFK agent to
navigate: there is no structural signal about which files change
together.

## Solution

Reorganize `.os/lib/` into domain folders, move orchestration logic out
of `02-wipe.sh` into a Disk Wipe module, split the Layout Module's pure
planning out of its destructive execution, isolate the one interactive
prompt behind a seam, and relocate test-only modules into the test tree.

The work runs in two phases:

1. **Mechanical move** — relocate and rename files into the approved
   folder taxonomy. Public function names stay stable; only file paths
   change. Behavior-preserving; existing tests must pass untouched
   except for `source` path updates.
2. **Deepen** — extract the new pure modules (`layout/plan`,
   `wipe/prior-state`), thin `02-wipe.sh` to an orchestrator, and put
   the Layout interactive leftover-disk prompt behind an adapter seam.

Target `lib/` taxonomy (singletons stay at root; a folder is created
only when ≥2 related files justify it):

```
lib/
  common.sh globals.sh jsonc.sh        # primitives (root)
  install-state.sh finalize.sh          # singletons (root)
  grub-common.sh live-medium.sh         # shared cross-domain (root)
  secrets.sh impermanence-common.sh     # domain singletons (root)
  picker.sh                             # (tools/pick.sh stays)
  shell/ shell-stdlib.sh                # unchanged
  chroot/ chroot.sh                     # unchanged
  config/   lifecycle accessors layers
            generator categorized-list
            validation environment
  zfs/      module pools verify pool-owners
  layout/   common single multi  +plan (new)
  wipe/     method targets progress  +prior-state (new)
  packages/ list kernel iso-resolver
  profiles/ runner program-runner
```

Config-cluster rename mapping (approved):

```
config.sh            -> config/lifecycle.sh
  (load_config, detect_mode, print_summary, generate_template)
install-config.sh    -> config/accessors.sh
  (install_config_get + schema getters)
configs.sh           -> config/layers.sh
  (host/user core+specific merge, program registry/validation)
configs-generator.sh -> config/generator.sh   (cg_*)
categorized-list.sh  -> config/categorized-list.sh
validation.sh        -> config/validation.sh
environment.sh       -> config/environment.sh
```

Test-only modules move out of `lib/` into the test tree:

```
tests/vm/lib/  vm-pool-verify  seed-generator  sentinel-watcher
```

## User Stories

1. As an installer maintainer, I want each domain to have its own
   folder under `lib/`, so that understanding the Layout Module means
   opening `lib/layout/` rather than grepping a flat directory.
2. As an installer maintainer, I want files grouped so that the files
   that change together live together, so that a domain change has
   locality.
3. As a contributor, I want a folder to exist only when ≥2 related
   files justify it, so that singletons stay at the root and the tree
   doesn't sprout one-file folders.
4. As an AFK agent, I want the directory structure to signal which
   files belong to one module, so that I can scope a change without
   reading every file.
5. As an installer maintainer, I want `02-wipe.sh` to read as an
   orchestrator that calls the Disk Wipe module, so that device-aware
   wipe logic lives behind a testable interface instead of inline in the
   install step.
6. As a test author, I want the Disk Wipe's prior-state detection
   (which target disks are already zeroed vs. carry signatures) as a
   pure function, so that I can assert its decisions without a real
   block device.
7. As an installer maintainer, I want the Layout Module's planning
   separated from its destructive execution, so that "what will be
   partitioned" is decided by a pure function before any disk is
   touched.
8. As a test author, I want `layout_plan` to be a pure function that
   emits the normalized layout record, so that I can test topology
   decisions without partitioning a disk.
9. As an installer maintainer, I want the Layout interactive
   leftover-disk prompt isolated behind a seam, so that the planner is
   pure and the prompt becomes a replaceable adapter.
10. As a test author, I want to substitute a non-interactive adapter
    for the leftover-disk prompt in tests, so that layout planning is
    testable without a TTY.
11. As a contributor, I want the Config cluster renamed into
    `config/` with intent-revealing names (`lifecycle`, `accessors`,
    `layers`, `generator`), so that I can tell what each file owns
    without opening it.
12. As an installer maintainer, I want public function names to stay
    stable across the move, so that grep for a function still finds it
    and call sites change only their `source` paths.
13. As a contributor, I want test-only modules out of `lib/`, so that
    what the installer sources is unambiguous and test infrastructure
    lives in the test tree.
14. As a test author, I want `tests/` to mirror the new `lib/` folder
    structure, so that the test for a module is at the predictable
    mirrored path.
15. As a test author, I want duplicated test-harness logic deduped when
    the test-only modules relocate, so that there is one harness, not
    copies.
16. As an installer maintainer, I want the refactor sequenced as a
    behavior-preserving mechanical move first, then deepening, so that
    each phase is reviewable in isolation and regressions are bisectable.
17. As a maintainer, I want the new architectural decisions captured in
    new ADRs, so that the rationale is recorded without rewriting paths
    in historical ADRs.
18. As a contributor reading an old ADR, I want it left as a historical
    record, so that the decision log reflects what was true when the
    decision was made, not the post-refactor paths.
19. As an installer maintainer, I want the ZFS files grouped under
    `lib/zfs/` (module, pools, verify, pool-owners), so that the ZFS
    surface is one folder.
20. As an installer maintainer, I want package-related files under
    `lib/packages/` (list, kernel, iso-resolver), so that package
    resolution is one folder.
21. As an installer maintainer, I want the Profiles Runner and Program
    Runner under `lib/profiles/`, so that profile execution is one
    folder.
22. As a maintainer, I want primitives and cross-domain singletons to
    stay at the `lib/` root, so that `common`, `globals`, `jsonc`,
    `install-state`, `finalize`, `grub-common`, `live-medium`,
    `secrets`, `impermanence-common`, and `picker` are easy to find.
23. As a contributor, I want `lib/shell/` and `lib/chroot/` left
    unchanged, so that the refactor doesn't churn already-organized
    subtrees.
24. As an installer maintainer, I want the install flow to behave
    identically before and after the mechanical-move phase, so that the
    move can land independently of any deepening.

## Implementation Decisions

- **Scope is four candidates plus test-infra relocation:** (1) foldered
  `lib/` taxonomy, (2) thin the Disk Wipe, (3) Layout planner/executor
  split, (4) Config cluster rename, and (5) relocate test-only modules
  with harness dedup.
- **Two-phase sequencing — mechanical move first, then deepen.** Phase 1
  is a pure relocate+rename with `source`-path updates and no behavior
  change. Phase 2 extracts new modules and isolates the prompt. Each
  phase is a separately reviewable unit.
- **Rename files freely.** File names change to fit the new folders and
  to read clearly (the Config mapping above). This is preferred over
  move-only.
- **Public function names stay stable.** Only file paths move. Layout
  verbs (`layout_validate`, `layout_plan`, `layout_partition`,
  `layout_create_pools`, `layout_mount_esp`), `install_config_*`, `cg_*`,
  and all other public identifiers keep their names. Call sites change
  their `source` line, not their calls.
- **Folder rule: a folder needs ≥2 related files.** Singletons stay at
  the `lib/` root. This governs which files fold into `config/`, `zfs/`,
  `layout/`, `wipe/`, `packages/`, `profiles/` and which stay flat.
- **Disk Wipe module owns the logic; `02-wipe.sh` becomes a thin
  orchestrator.** Device-aware wipe behavior (blkdiscard on SSD/NVMe,
  zero-pass on HDD, parallel per-disk progress) moves into `lib/wipe/`.
  The install step calls the module. The two safety invariants are
  preserved exactly: the live medium is never listed/selectable/wipeable
  (multi-signal detection, not string match), and an install-driven wipe
  touches only the resolved target set (`os_pool` + `storage_groups` +
  `data_pools`).
- **New module `lib/wipe/prior-state.sh` (pure).** Extracts the
  "is this disk already zeroed / does it carry signatures" decision out
  of the wipe execution path so it is a pure function over probed disk
  facts, returning the set to wipe.
- **Layout planner/executor split via new `lib/layout/plan.sh`
  (pure).** `layout_plan` becomes a pure function that consumes resolved
  config and emits the normalized layout record
  (`LAYOUT_ESP_PARTS[]`, `LAYOUT_OS_POOL_NAME`,
  `LAYOUT_DATA_POOL_NAME`). Destructive verbs (`layout_partition`,
  `layout_create_pools`, `layout_mount_esp`) stay in the mode adapters
  (`single`, `multi`) behind `layout/common`. The phase-lifecycle
  ordering (validate→plan→partition→pools→esp, enforced via
  `_layout_enter_phase`/`_layout_exit_phase`) is preserved; ADR 0016
  is not re-litigated. ADR 0014 (adapter owns validation) is preserved.
- **Layout interactive leftover-disk prompt isolated behind a seam.**
  The install-time TTY prompt becomes an adapter satisfying a small
  interface, so the planner is pure and a non-interactive adapter can be
  substituted in tests. The prompt is not relocated to the picker.
- **Config cluster renamed into `lib/config/`** per the approved mapping
  (`lifecycle`, `accessors`, `layers`, `generator`, `categorized-list`,
  `validation`, `environment`). Schema-driven accessors (ADR 0015),
  categorized-list schema (ADR 0022), and environment-resolution
  self-containment (ADR 0017) are preserved — only the files move.
- **Test-only modules relocate to `tests/vm/lib/`** (`vm-pool-verify`,
  `seed-generator`, `sentinel-watcher`) and the test harness is deduped
  in the process so there is a single harness.
- **`tests/` mirrors the new `lib/` folder structure** so each module's
  test sits at the mirrored path; test files relocate alongside the
  modules and tests stay co-located by domain.
- **New ADRs capture the new decisions** (folder taxonomy, Disk Wipe
  module extraction, Layout planner/executor split, leftover-prompt
  seam). Historical ADRs (0012–0031) are left as-is — paths in them are
  not rewritten. New ADRs continue numbering from 0032.

## Testing Decisions

A good test here asserts external behavior — the value a pure function
returns for given inputs, or the record a planner emits — not which file
a function lives in or how it is wired internally. The mechanical-move
phase is behavior-preserving, so its safety net is the existing suite
passing unchanged.

- **Test scope: pure logic + seam-testable.** Newly-extracted pure
  modules are tested directly; behavior reachable through a substituted
  adapter at a seam is tested via that seam. I/O orchestration
  (real partitioning, real `blkdiscard`, real pool creation) is not
  unit-tested here — that stays covered by the VM smoke tests.
- **`lib/wipe/prior-state.sh`** — pure tests over probed disk facts:
  a disk with no signatures is reported as already-blank; a disk with
  ZFS/LVM/MD labels or a partition table is reported as needing a wipe;
  the resolved target set excludes the live medium. Prior art:
  `disk-wipe-ux` tests.
- **`lib/layout/plan.sh`** — `layout_plan` emits the expected
  normalized record for single-mode and multi-mode inputs (correct
  `LAYOUT_ESP_PARTS[]` ordering with primary at index 0, correct
  `LAYOUT_OS_POOL_NAME`, empty `LAYOUT_DATA_POOL_NAME` when no data
  pool). `layout_validate` remains a pure check with no state writes.
  Prior art: `layout-adapter-owns-validation`,
  `layout-phase-lifecycle` tests.
- **Layout leftover-disk seam** — a test substitutes a non-interactive
  adapter and asserts the planner produces a plan without a TTY, and
  that the adapter's choice flows into the plan.
- **Mechanical-move regression** — the entire existing bats suite passes
  after Phase 1 with only `source` paths updated. Any new failure means
  a missed relocation, not a behavior change.
- **Test harness** — after dedup there is a single harness; the
  relocated `tests/vm/lib/` modules are sourced from the one place.

## Out of Scope

- Changing any Install Config schema, Layout interface contract, or the
  Disk Wipe safety invariants. This is a structure refactor, not a
  behavior change.
- Renaming public function names. Only file paths and module file names
  change.
- Restructuring `lib/shell/` or `lib/chroot/` — both stay as-is.
- Multi-pass/forensic erase in the Disk Wipe (still out of scope, as
  today).
- Multi-kernel bootloader/preset wiring (tracked elsewhere).
- Rewriting paths in historical ADRs (0012–0031).
- Unit-testing I/O orchestration (real partitioning, pool creation,
  block-device wipes) — remains the VM smoke tests' job.
- Relocating the Layout leftover-disk prompt into the picker (rejected
  in favor of the seam).

## Further Notes

- The mechanical-move phase is the riskiest for silent breakage via
  stale `source` paths; sequencing it first and gating on the full
  existing suite is the mitigation.
- Once `layout_plan` is pure, future work could surface a dry-run
  "show the plan" mode for free; not in scope here.
- Once `wipe/prior-state` is pure, the standalone `02-wipe.sh` run path
  and the install-driven path share the same decision function.
- New ADR candidates: lib/ folder taxonomy + folder-needs-≥2-files rule;
  Disk Wipe module extraction; Layout planner/executor split; Layout
  leftover-disk prompt seam.
