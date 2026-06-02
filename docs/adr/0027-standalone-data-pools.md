# ADR 0027: Standalone Data Pools as a distinct concept

## Status
Accepted

## Context
Multi-disk mode produced at most one data pool: a single `dpool`
assembled from one-or-more Storage Groups (`storage_groups[]`), each
folded in as a vdev under `dpool/DATA/<name>`. Every storage disk
therefore shared one pool and one failure domain — a single
non-redundant disk loss degrades or destroys the whole `dpool`.

The `independent` storage topology looks like it solves this but does
not: it only splits a group into per-disk *datasets* inside the same
`dpool`. The disks still stripe at the pool level, so they still share
fate.

The real-world need: disks of *different sizes* where the operator
wants the OS on one disk and each remaining disk as its own pool —
independent failure domains, no cross-disk striping. The existing
model could not express "each disk is its own pool."

## Decision
Introduce a new first-class Install Config concept, the **Standalone
Data Pool**, declared in a top-level `data_pools[]` array. Each entry
becomes its own `zpool create`:

- Fields: `name` (the zpool name) and `disks` (≥1) required;
  `topology` (default `stripe`), `mount` (default `/data/<name>`),
  `ashift` (default 12) optional.
- Allowed topologies: `stripe | mirror | raidz1 | raidz2`. `none` and
  `independent` are **rejected at validation** with guidance, because
  on a standalone pool `none` silently drops all but the first disk
  (see `build_vdev_spec`), and both cases are already expressible
  ("each disk separate" = multiple entries; "all disks, no redundancy"
  = `stripe`).
- Data lives in a single child dataset `<name>/data` mounted at
  `mount`; the pool root stays unmounted (matches single-mode
  `dpool/storage` house style).
- Encryption inherits the global `options.encryption` (same passphrase
  via `build_enc_opts`) — no per-pool keys in v1.
- Multi-disk only. Orthogonal to `storage_groups[]`: both may be
  present (some disks pooled together, others standalone).
- Also producible interactively: when OS topology is `none`, the
  leftover-disk flow asks per-disk whether each leftover folds into the
  Combined Data Pool (today's behavior) or becomes its own Standalone
  Data Pool (named at the prompt, default `dataN`, mount
  `/data/<name>`). Interactive path is single-disk pools only; mirror/
  raidz standalone pools require declarative `data_pools[]`.

The layout state contract changes: the scalar `LAYOUT_DATA_POOL_NAME`
is **replaced** (not supplemented — it had a single reader) by a list
`LAYOUT_DATA_POOL_NAMES[]` holding the Combined Data Pool (when present)
plus every Standalone Data Pool, so `finalize` loops it for export and
recovery hints. The zpool.cache seeding already loops over all pools
(`_chroot_seed_zpool_cache`), so boot-time import of N pools needs no
change.

The **Pre-Install Picker is out of scope**: like `storage_groups`,
`data_pools[]` is template/hand-authored. Only the interactive
leftover flow inside `layout-multi.sh` gains a path.

Per ADR 0014, all new validation lives in the multi adapter's
`layout_validate`:

- **Name** — each `data_pools[].name` must match
  `^[a-zA-Z][a-zA-Z0-9_-]*$` and is rejected if it is a ZFS reserved
  vdev word (`mirror`, `raidz1?`/`raidz2`/`raidz3`, `draid*`, `spare`,
  `log`, `cache`, `special`, `dedup`) or a `cN` prefix. A shared
  `_zfs_valid_pool_name` helper owns this (retrofitting it to
  `os_pool_name`/`storage_pool_name` is out of scope).
- **Uniqueness** — names unique across rpool + dpool + all data pools;
  no disk reused across OS pool / storage groups / data pools; disks
  exist as block devices.
- **Mount** — fatal on exact-duplicate mountpoints (across all declared
  storage mounts) or a mount equal to an OS/reserved path
  (`/`, `/home`, `/var*`, `/boot*`, `/tmp`, `/persist`); nested mounts
  (`/data` + `/data/tank0`) are allowed.
- **Topology vs count** — mirror ≥2, raidz1 ≥2, raidz2 ≥3, etc.

One **non-fatal warning** (not in `layout_validate`, emitted at plan
time): a redundant topology (mirror/raidz1/raidz2) across disks of
differing sizes warns that usable space caps to the smallest member.

## Considered alternatives
- **`standalone: true` flag on `storage_groups[]`.** Rejected: muddies
  the Storage Group definition ("a vdev in the shared dpool") by making
  some entries not be in the dpool at all. One array would then mean
  two opposite things.
- **Overload `topology` with a `separate-pools` value.** Rejected:
  `topology` describes vdev arrangement *within* a pool; using it to
  draw pool *boundaries* conflates two axes and collides with the
  existing `independent`.
- **Reuse the `independent` topology.** Rejected: it keeps disks in one
  pool/failure domain — the exact thing this feature exists to avoid.
- **Per-pool encryption now.** Deferred: adds multi-passphrase keying
  complexity for a v1 nobody has asked for; global inheritance matches
  rpool/dpool today.

## Consequences
- Two ways to express multi-disk storage now coexist: Storage Groups
  (pooled together, shared failure domain) and Standalone Data Pools
  (independent failure domains). The glossary and `install.jsonc`
  examples must make the distinction explicit so operators pick
  deliberately.
- `LAYOUT_DATA_POOL_NAME` consumers (`finalize.sh`, `globals.sh`
  contract) move from a single name to a list.
- Adding standalone pools means new partition + pool-creation paths in
  `layout-multi.sh` (a loop over `data_pools[]` plus interactively
  synthesized entries), and new `layout_validate` checks — no other
  adapter or downstream module changes.
- Single mode is untouched: it remains one disk = ESP + rpool + dpool.
