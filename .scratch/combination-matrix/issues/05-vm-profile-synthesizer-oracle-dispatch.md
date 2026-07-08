# 05 — VM-profile synthesizer + oracle dispatch

Status: done
Type: AFK

## Parent

`.scratch/combination-matrix/PRD.md`

## What to build

Turn any generated cell into a ready-to-run ephemeral VM Profile, and route each
cell to the right oracle:

- **Synthesizer** (pure) — cell → VM Profile JSON: `hardware.disks` = Σ
  `disk_count` across os_pool + storage_groups + data_pools (via
  `skeleton_total_disks`) at 20 GiB each; `verify` block chosen from the oracle
  table; `timeouts.install` from the light/heavy band (heavy = any desktop,
  nvidia, or AUR).
- **Oracle dispatch** — plain cells verify to the first-boot sentinel;
  impermanent cells set `verify.rollback` (two-boot: ephemeral wiped, persistent
  survived); `gpu≠auto` cells assert clean driver-package install (install-only,
  no functional GPU check). Encrypted cells are wired for boot-verify but the
  actual unlock lands in issue 07 — until then they run install-only.

Wire `matrix.sh emit`/`run` to use the synthesizer instead of issue-01's fixed
profile. Resilience axes (`by_id`, `reorder_boot_disks`, `resilience`,
`dirty_cache`) are NOT set here — they stay on curated profiles.

## Acceptance criteria

- [x] Disk count for each topology matches Σ disk_count (single→1, mirror/raid1→
      2, raidz1→3, raidz2→4, + data-pool disks).
- [x] The `verify` block matches the oracle table for plain / impermanent /
      encrypted / gpu≠auto cells.
- [x] `timeouts.install` matches the light/heavy band for representative cells;
      env override still wins (vm.sh honours `INSTALL_TIMEOUT_SEC` over the
      profile's `timeouts.install`).
- [x] An impermanent cell installs and passes `verify.rollback` in a VM.
- [x] Unit tests cover disk/verify/timeout derivation across representative
      cells.

## Blocked by

- `.scratch/combination-matrix/issues/01-tracer-bullet-spine.md`
- `.scratch/combination-matrix/issues/04-cell-generator-constraints-mixed-fs-seeds.md`

## Comments

**Done 2026-07-08 (TDD, LOCAL/UNPUSHED).** `lib/matrix/synth.sh`:
`matrix_cell_synthesize <cell>` → VM Profile. `hardware.disks` = Σ disk_count
(root topology + data pool) each `MATRIX_DISK_GIB`; `verify` from the oracle
(`matrix_cell_verify`/`matrix_cell_boot_verify`): plain→`{boot}`, impermanent→
`{boot,rollback}`, encrypted or gpu≠auto→install-only (no verify block, no
`--verify-boot`); `timeouts.install` from `matrix_cell_timeout` light(2700)/
heavy(5400), heavy = any desktop or nvidia.

Assembler extended: `options.impermanence.enabled` from the cell (dataset
defaults to rpool/persist); multi cells bake the `os_pool` skeleton + N-disk
assignment (`/dev/sd{a..}`). `matrix_cell_profile`→synthesizer; `matrix_run`
passes `--verify-boot` only when the oracle says so. Tier-1 assembly bats now
also validates an impermanent-single + a multi-mirror cell. 38 matrix bats,
shellcheck clean.

**VM FINDING (real):** the PRD's 20 GiB/disk is too small — a zfs root with the
default ~5 GiB swap zvol + OS + impermanence datasets overflows a ~16 GiB rpool
(`cannot create rpool/swap: out of space`, VM-observed). Bumped
`MATRIX_DISK_GIB` default to **40** (qcow2 is sparse → free); recorded in
`docs/agents/combination-matrix.md`. **AC4 VM: impermanent zfs-single installs +
passes `verify.rollback`** (two-boot proof) at 40 GiB.

**Deferred:** data-pool DISK baking (mixed-fs cells provision the extra disk but
install root-only, disk unused); encrypted boot-verify (issue 07, install-only
until the Console Answerer).
