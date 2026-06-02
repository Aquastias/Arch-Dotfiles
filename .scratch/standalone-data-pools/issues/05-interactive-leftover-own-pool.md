# 05 — Interactive leftover per-disk own-pool

Status: ready-for-human

## Parent

`.scratch/standalone-data-pools/PRD.md` (ADR 0027).

## What to build

Let an operator create Standalone Data Pools interactively. When the OS
pool topology is `none` and there are leftover disks, ask per disk
whether each leftover folds into the Combined Data Pool (today's
behaviour) or becomes its own Standalone Data Pool.

Scope:

- Change the `topology=none` leftover flow from a single group-wide
  topology choice to a per-disk choice: fold vs own-pool.
- For an own-pool choice: prompt for a name (default `dataN`), set mount
  `/data/<name>`, single-disk `stripe`. Validate the entered name with
  `_zfs_valid_pool_name` and the uniqueness/mount rules.
- Synthesize these into the same internal data-pool structure consumed
  by the partition and pool-creation steps from 01 — interactively
  created pools and declarative `data_pools[]` go through one path.
- Folded leftovers keep today's behaviour (into the Combined Data Pool).
- Interactive path is single-disk `stripe` only; redundant standalone
  pools remain declarative-only.

## Acceptance criteria

- [ ] With `topology=none` and 2+ leftover disks, each leftover prompts
      fold vs own-pool independently (mixing allowed).
- [ ] Choosing own-pool prompts a name (default `dataN`); the resulting
      pool is single-disk `stripe` mounted at `/data/<name>` with a
      `<name>/data` dataset.
- [ ] An entered name failing the name/uniqueness/mount rules is
      re-prompted or aborts with the standard message.
- [ ] Folded leftovers still land in the Combined Data Pool.
- [ ] Interactively-created pools are exported at finalize and import on
      boot like declarative ones.

## Blocked by

- 01 — Declarative standalone data pool (single-disk, end-to-end)
- 03 — Pool-name + uniqueness + mount validation
