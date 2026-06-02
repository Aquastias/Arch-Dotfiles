# PRD: Standalone Data Pools

Status: done

See ADR 0027 (`docs/adr/0027-standalone-data-pools.md`) and the
glossary entries **Standalone Data Pool**, **Storage Group**,
**Combined Data Pool** in `CONTEXT.md`.

## Problem Statement

I have several disks of different sizes. I want the OS on one disk
and each remaining disk to be its own data pool — independent, so one
disk dying never affects the others.

Today multi-disk mode can only produce a single Combined Data Pool
(`dpool`) assembled from Storage Groups. Every storage disk shares one
pool and one failure domain: a non-redundant disk loss degrades or
destroys the whole `dpool`. The `independent` topology looks like it
solves this but doesn't — it only splits a group into per-disk
datasets inside the same pool, so the disks still stripe at pool level
and still share fate. There is no way to say "each disk is its own
pool."

## Solution

A new first-class Install Config concept, the **Standalone Data Pool**,
declared in a top-level `data_pools[]` array. Each entry becomes its
own `zpool` with its own name, mountpoint, topology, and failure
domain. It sits alongside `storage_groups[]` (which keeps meaning
"fold into the shared Combined Data Pool") — an operator can use
either or both.

Standalone pools can also be produced interactively: when OS topology
is `none`, the leftover-disk flow asks, per disk, whether each leftover
folds into the Combined Data Pool (today's behaviour) or becomes its
own Standalone Data Pool.

## User Stories

1. As an operator with mixed-size disks, I want each non-OS disk to be
   its own pool, so that one disk failing leaves the others fully
   intact.
2. As an operator, I want to declare a `data_pools[]` array in
   `install.jsonc`, so that my storage layout is reproducible from
   config.
3. As an operator, I want each `data_pools[]` entry to take a `name`
   that becomes the literal zpool name, so that my pools are named
   meaningfully (e.g. `tank-photos`).
4. As an operator, I want each entry to require only `name` and
   `disks`, so that simple single-disk pools are terse.
5. As an operator, I want `topology` to default to `stripe`, so that a
   single-disk pool needs no topology line.
6. As an operator, I want `mount` to default to `/data/<name>`, so
   that I don't have to spell out a mountpoint per pool.
7. As an operator, I want `ashift` to default to 12, so that typical
   disks need no tuning.
8. As an operator, I want a multi-disk standalone pool with `mirror`,
   `raidz1`, or `raidz2`, so that a single pool can be redundant.
9. As an operator, I want to express "all disks in one pool, no
   redundancy" as `stripe`, so that there's an obvious non-redundant
   multi-disk option.
10. As an operator, I want "each disk separate" expressed as multiple
    `data_pools[]` entries, so that the separation is explicit.
11. As an operator, I want `none` and `independent` rejected for
    `data_pools` with a guiding error, so that I don't silently lose
    disks (`none` would use only the first disk).
12. As an operator, I want an invalid pool name (bad characters,
    leading digit, a ZFS reserved word like `mirror`, or a `cN`
    prefix) rejected at config time, so that I get a clear error
    instead of a cryptic `zpool create` failure.
13. As an operator, I want duplicate pool names (across rpool, dpool,
    and all data pools) rejected, so that pools can't collide.
14. As an operator, I want a disk used in more than one place (OS pool,
    a storage group, or another data pool) rejected, so that I don't
    double-allocate a disk.
15. As an operator, I want a non-existent disk path rejected before any
    destructive operation, so that a typo fails safely.
16. As an operator, I want a topology that needs more disks than I
    listed (e.g. `mirror` with one disk) rejected, so that the pool is
    creatable.
17. As an operator, I want two pools claiming the same mountpoint
    rejected, so that one doesn't silently shadow the other.
18. As an operator, I want a data pool mounted at an OS/reserved path
    (`/`, `/home`, `/var*`, `/boot*`, `/tmp`, `/persist`) rejected, so
    that I can't shadow an OS dataset and break boot.
19. As an operator, I want nested mounts (`/data` and `/data/tank0`)
    allowed, so that legitimate layered layouts work.
20. As an operator, I want a non-fatal warning when a redundant pool
    spans unequal-size disks, so that I know usable space caps to the
    smallest member before I commit.
21. As an operator who installs interactively, when OS topology is
    `none`, I want to choose per leftover disk whether it folds into
    `dpool` or becomes its own pool, so that I can decide without
    editing config.
22. As an operator, when I choose "own pool" for a leftover disk
    interactively, I want to be prompted for a name (default `dataN`),
    so that I can label it inline.
23. As an operator, I want interactively-created standalone pools to be
    single-disk `stripe`, so that the simple case needs no extra
    prompts; redundant standalone pools go through declarative config.
24. As an operator, I want my standalone pools encrypted whenever
    `options.encryption` is true, so that they match the OS pool with
    the same passphrase.
25. As an operator, I want each standalone pool's data in a child
    dataset (`<name>/data`) at the mountpoint with the pool root
    unmounted, so that the layout matches the existing dpool
    convention and the data dataset can be snapshotted/replicated.
26. As an operator, I want all my pools (OS, combined, standalone)
    imported automatically on first boot, so that the system comes up
    with everything mounted.
27. As an operator, I want all pools exported cleanly at the end of
    install, so that they import without `-f` on the new system.
28. As an operator, I want the post-install recovery hint to list
    every pool, so that I can recover any of them from the live ISO.
29. As an operator, I want `data_pools` to be multi-disk-mode only and
    single mode unchanged, so that existing single-disk installs are
    unaffected.
30. As an operator, I want `storage_groups` and `data_pools` to coexist
    in one config, so that I can mix a redundant shared pool with
    standalone pools.
31. As an operator, I want a worked `data_pools[]` example in
    `install.jsonc`, so that I can copy a known-good shape.
32. As a maintainer, I want a clear domain distinction between Storage
    Group, Combined Data Pool, and Standalone Data Pool in the
    glossary, so that future readers pick the right concept.

## Implementation Decisions

**New concept / schema**

- New top-level `data_pools[]` array in the Install Config. Each entry:
  `name` (required, the zpool name), `disks` (required, ≥1),
  `topology` (optional, default `stripe`), `mount` (optional, default
  `/data/<name>`), `ashift` (optional, default 12).
- Allowed topologies: `stripe | mirror | raidz1 | raidz2`. `none` and
  `independent` are rejected at validation with a guiding error.
- Standalone-pool dataset layout: pool root `canmount=off`; one child
  dataset `<name>/data` mounted at `mount`. Matches single-mode
  `dpool/storage` house style.
- Encryption inherits the global `options.encryption` (same passphrase
  via the existing encryption-options builder). No per-pool keys.
- Multi-disk mode only. Single mode is untouched. `data_pools` and
  `storage_groups` may both be present.

**Modules — deep / pure**

- **`_zfs_valid_pool_name`** — new pure helper (in the ZFS pools
  module). Input: a candidate name. Output: ok, or a reason. Enforces
  `^[a-zA-Z][a-zA-Z0-9_-]*$`, rejects ZFS reserved vdev words
  (`mirror`, `raidz1`/`raidz2`/`raidz3`, `draid*`, `spare`, `log`,
  `cache`, `special`, `dedup`) and `cN` prefixes. Retrofitting it onto
  `os_pool_name`/`storage_pool_name` is out of scope.
- **`data_pools[]` Install Config accessors** — typed readers: entry
  count, and per-entry `name`/`disks`/`topology`/`mount`/`ashift` with
  the defaults above applied. Mirrors the existing storage-group ashift
  accessor style.
- **Unequal-disk size check** — pure decision: given a vdev's disk
  sizes and topology, return whether to warn (redundant topology +
  sizes differ). Drives a non-fatal `warn` at plan time, not in
  `layout_validate`.

**Modules — multi Layout Adapter (modified)**

- **`layout_validate`** gains all data_pool validation (per ADR 0014,
  validation lives in the adapter, is a pure check, exits via `error`
  on first failure): name rules (via `_zfs_valid_pool_name`),
  uniqueness of names across rpool + dpool + all data pools, no disk
  reuse across OS pool / storage groups / data pools, disk existence as
  block devices, topology-vs-disk-count, mountpoint dupes, mountpoint
  equal to an OS/reserved path. Nested mounts allowed.
- **Plan** — a `resolve_data_pools` step reads declarative
  `data_pools[]` and also receives entries synthesized from the
  interactive leftover own-pool choice, into one internal data-pool
  structure consumed by partition and pool-creation.
- **Leftover prompt** — the topology=`none` flow changes from a single
  group-wide topology choice to a per-disk choice: fold into the
  Combined Data Pool (today) or become a Standalone Data Pool
  (prompt name, default `dataN`, mount `/data/<name>`, single-disk
  `stripe`). Folded leftovers keep today's behaviour.
- **Partition** — `partition_data_pools`: one ZFS partition per disk in
  each standalone pool.
- **Pool creation** — `create_data_pools`: loop over the data-pool
  structure; build the vdev spec from topology + partitions; create the
  pool with the standard pool settings and inherited encryption; create
  the `<name>/data` child dataset at `mount`.
- These hang off the existing seam verbs (`layout_plan`,
  `layout_partition`, `layout_create_pools`) and respect the phase
  lifecycle (ADR 0016).

**Cross-cutting**

- **LAYOUT contract** — replace the scalar `LAYOUT_DATA_POOL_NAME` with
  a list `LAYOUT_DATA_POOL_NAMES[]` holding the Combined Data Pool
  (when present) plus every Standalone Data Pool. Single mode populates
  it with its one dpool; multi mode populates dpool (if any) +
  standalone names. The single existing reader (`finalize`) loops the
  list for both pool export and the recovery hint. Update the contract
  documentation in the globals module.
- **Boot import** — no change needed: the zpool.cache seeding already
  loops over every imported pool, so N pools are cached and imported on
  first boot automatically.
- **`install.jsonc`** — add a worked `data_pools[]` example block and
  update the mode comments.

**Out-of-scope confirmations**

- Pre-Install Picker (`tools/pick.sh`) is untouched — like
  `storage_groups`, `data_pools` is template/hand-authored.

## Testing Decisions

A good test asserts **external behaviour**, not implementation: given a
config (or inputs), the right pools/datasets/validation-outcomes/exports
result. Tests use the project's `bats` unit suites with fixture configs
(no real disks), plus one VM smoke test for the real `zpool`/`sgdisk`
paths that unit tests can't exercise.

Modules to test:

- **`_zfs_valid_pool_name`** — unit. Valid names (`tank0`,
  `tank-photos`), and each rejection class (leading digit, reserved
  word `mirror`/`raidz1`, `cN` prefix, illegal char like `.`). Prior
  art: `tests/zfs-pools.bats`.
- **`layout_validate` data_pool rules** — unit. Duplicate name; disk
  reused across `os_pool`/storage group/another data pool; non-existent
  disk; topology needing more disks than listed (`mirror` w/1);
  duplicate mountpoint; mount equal to a reserved path (`/home`);
  nested mounts accepted; `none`/`independent` rejected. Prior art:
  `tests/layout-multi.bats`.
- **Config accessors + size-warn** — unit. Defaults applied (absent
  `mount` → `/data/<name>`, absent `topology` → `stripe`, absent
  `ashift` → 12); entry count; the unequal-disk warn decision returns
  true for a redundant topology over differing sizes and false for
  equal sizes / stripe / single disk. Prior art:
  `tests/install-config.bats`.
- **finalize + VM smoke** — `finalize` exports every pool in
  `LAYOUT_DATA_POOL_NAMES[]` and lists each in the recovery hint
  (prior art: `tests/finalize.bats`). New VM smoke test (sibling of
  `tests/vm/testing-multi-os-none.sh`): one OS disk plus two standalone
  data pools; assert the machine boots, all pools import, and the
  `<name>/data` datasets are mounted at their mountpoints.

## Out of Scope

- Per-pool encryption / per-pool passphrases (v1 inherits global
  `options.encryption`).
- Pre-Install Picker changes — `data_pools` is config/template-authored.
- Interactive creation of redundant (`mirror`/`raidz`) standalone pools
  — interactive path is single-disk `stripe` only; redundant standalone
  pools require declarative `data_pools[]`.
- Retrofitting `_zfs_valid_pool_name` onto the existing
  `os_pool_name`/`storage_pool_name` fields.
- Single-disk mode changes.
- Cross-pool features (e.g. shared L2ARC/SLOG, auto-replication).

## Further Notes

- Domain language: a **Standalone Data Pool** (own pool, own failure
  domain) is deliberately distinct from a **Storage Group** (a vdev
  folded into the shared **Combined Data Pool**). The interactive
  leftover flow is the only place the two meet — each leftover disk
  goes one way or the other.
- The `none`-rejection matters: `build_vdev_spec` maps `none` to "first
  disk only", so allowing it on a multi-disk data pool would silently
  drop disks. The validation error points operators to `stripe` (one
  pool) or multiple entries (separate pools).
- Respect ADR 0014 (adapter owns validation) and ADR 0016 (phase
  lifecycle) when wiring the new verbs.
