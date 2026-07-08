# 08 — Coverage summary + manifest + CI diff + docs

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/combination-matrix/PRD.md`

## What to build

Make coverage a committed, enforced record:

- **Matrix Manifest** (`.os/tests/vm/matrix-manifest.jsonl`) — commit the
  **Tier-2 set** (one line per cell: cell-id + axis assignment): the expensive,
  selective cells worth reviewing/pinning/reproducing.
- **Coverage summary** (pure) — a committed, diffable snapshot of resolved axes
  → values → exclusions + per-tier cell counts (e.g. `storage-cluster: 36`); the
  drift guard for the constraint model (a silent shrink Tier-1 bats alone would
  not catch, since it still passes with fewer valid cells).
- **CI diff** — a job that runs `matrix.sh gen`, regenerates both records, and
  diffs them against the committed snapshots, failing until regenerated and
  committed. Combined with issue-02's completeness assertion, a new menu option
  cannot merge without updating the matrix.
- **Docs** — record the "menu-derived, CI-enforced" sync contract under
  `docs/agents/` so menu-editing and `/improve-codebase-architecture` workflows
  know to run `matrix.sh gen` at wrap-up.

Tier-1's exhaustive list stays regenerated-live (not committed); VM Profiles are
never committed (materialized via `emit`).

## Acceptance criteria

- [ ] `matrix.sh gen` writes the Tier-2 manifest and the coverage summary
      deterministically.
- [ ] Coverage-summary counts match the generated sets; output is byte-stable
      across runs for identical inputs.
- [ ] A CI check regenerates both records and fails on any diff vs the committed
      snapshots (demonstrated by a deliberate axis-value change).
- [ ] Dropping a topology value (e.g. raidz2) shows as a one-line summary change
      + count delta, not a wall of vanished rows.
- [ ] `docs/agents/` documents the sync contract and the `matrix.sh gen`
      wrap-up step.

## Blocked by

- `.scratch/combination-matrix/issues/04-cell-generator-constraints-mixed-fs-seeds.md`
- `.scratch/combination-matrix/issues/06-host-guard-parallel-driver-summary.md`
