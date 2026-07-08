# 05 — VM-profile synthesizer + oracle dispatch

Status: ready-for-agent
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

- [ ] Disk count for each topology matches Σ disk_count (single→1, mirror/raid1→
      2, raidz1→3, raidz2→4, + data-pool disks).
- [ ] The `verify` block matches the oracle table for plain / impermanent /
      encrypted / gpu≠auto cells.
- [ ] `timeouts.install` matches the light/heavy band for representative cells;
      env override still wins.
- [ ] An impermanent cell installs and passes `verify.rollback` in a VM.
- [ ] Unit tests cover disk/verify/timeout derivation across representative
      cells.

## Blocked by

- `.scratch/combination-matrix/issues/01-tracer-bullet-spine.md`
- `.scratch/combination-matrix/issues/04-cell-generator-constraints-mixed-fs-seeds.md`
