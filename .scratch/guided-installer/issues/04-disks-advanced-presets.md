# Disks: multi-disk presets + Advanced skeleton authoring

Status: ready-for-agent

## Parent

`.scratch/guided-installer/PRD.md`

## What to build

Extend the Disks section beyond the single-disk preset. Add the ZFS
shape presets — OS mirror, OS mirror + raidz1 storage, OS `none` +
standalone data pools — that pre-fill a valid pool skeleton, plus an
**Advanced** door that authors the full skeleton by hand: `mode`,
`os_pool`, `storage_groups[]`, `data_pools[]` with
topology/ashift/`disk_count`/owners.

Reuse the existing pure topology rules (`suggest_os_topologies`,
`suggest_storage_topologies`) and `picker_validate_layout`; disk picking
and per-group assignment reuse `picker_build_assignment` /
`picker_assign_disks`, rendering the per-group assignment summary for
confirmation before accept.

## Acceptance criteria

- [ ] Presets pre-fill valid skeletons; Advanced authors arbitrary
      `os_pool` / `storage_groups` / `data_pools`.
- [ ] The skeleton builder agrees with `picker_validate_layout` and the
      min-disk table; an under-populated group is named in the error.
- [ ] Picked disks are sliced per-group by `disk_count` in declared
      order; the assignment summary is rendered and confirmed before
      accept.
- [ ] bats: skeleton-from-choices + validation reuse.
- [ ] VM smoke: a multi-disk guided install (e.g. mirror OS + raidz1
      storage) boots.

## Blocked by

- `01-guided-install-tracer-bullet`
