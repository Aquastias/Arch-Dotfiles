# 01 — Declarative standalone data pool (single-disk, end-to-end)

Status: ready-for-agent

## Parent

`.scratch/standalone-data-pools/PRD.md` (see ADR 0027 and the
**Standalone Data Pool** glossary entry in `CONTEXT.md`).

## What to build

The thinnest complete path for a **Standalone Data Pool**: a
`data_pools[]` entry in the Install Config with a single disk is created
as its own `zpool`, with a `<name>/data` child dataset mounted at the
configured mountpoint, exported cleanly at finalize, and imported
automatically on first boot.

This slice deliberately handles only the single-disk `stripe` case and
minimal validation (disk exists). Multi-disk topologies (02), full
name/mount validation (03), the size warning (04), and the interactive
path (05) come later.

Scope:

- New top-level `data_pools[]` array, multi-disk mode only. Single mode
  unchanged. Coexists with `storage_groups[]`.
- Typed Install Config accessors for `data_pools[]`: entry count and
  per-entry `name` (required), `disks` (required), `topology` (default
  `stripe`), `mount` (default `/data/<name>`), `ashift` (default 12).
- Multi Layout Adapter: resolve declarative entries during the plan
  phase; partition one ZFS partition per disk; create each pool with the
  standard pool settings and inherited global encryption; create the
  `<name>/data` child dataset (pool root `canmount=off`) at `mount`.
- Replace the scalar `LAYOUT_DATA_POOL_NAME` with the list
  `LAYOUT_DATA_POOL_NAMES[]` holding the Combined Data Pool (when
  present) plus every Standalone Data Pool. Update the layout contract
  doc. `finalize` loops the list for export and the recovery hint.
  Single mode populates it with its one dpool.
- Add a worked `data_pools[]` example block to `install.jsonc` and
  update the mode comments.
- Respect ADR 0014 (adapter owns validation) and ADR 0016 (phase
  lifecycle).

## Acceptance criteria

- [ ] A multi-mode config with one `data_pools[]` entry (single disk,
      defaults) creates a pool named `name` with a `<name>/data` dataset
      mounted at `/data/<name>`.
- [ ] `topology`, `mount`, `ashift` apply their defaults when omitted.
- [ ] When `options.encryption` is true, the standalone pool is
      encrypted with the same passphrase as rpool.
- [ ] `LAYOUT_DATA_POOL_NAMES[]` is populated in both single and multi
      modes; the scalar `LAYOUT_DATA_POOL_NAME` is gone.
- [ ] `finalize` exports every pool in the list and lists each in the
      recovery hint.
- [ ] All pools (rpool, dpool if any, standalone) import on first boot
      (zpool.cache seeding already loops all pools — verify no change
      needed).
- [ ] Single-disk mode behaviour is unchanged.
- [ ] `install.jsonc` contains a `data_pools[]` example.
- [ ] Unit tests cover the new config accessors and defaults (prior art:
      `tests/install-config.bats`); `finalize` array export/hint tests
      updated (prior art: `tests/finalize.bats`).

## Blocked by

None - can start immediately.
