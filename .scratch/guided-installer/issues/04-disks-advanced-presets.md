# Disks: multi-disk presets + Advanced skeleton authoring

Status: ready-for-agent

<!-- Presets + multi VM: DONE (2026-06-17). Advanced authoring: follow-up. -->
<!-- See ## Comments. -->


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

- [x] Presets pre-fill valid skeletons; Advanced authors arbitrary
      `os_pool` / `storage_groups` / `data_pools`. (Presets done; **Advanced
      authoring deferred to a follow-up** — user-approved scope.)
- [x] The skeleton builder agrees with `picker_validate_layout` and the
      min-disk table; an under-populated group is named in the error.
- [x] Picked disks are sliced per-group by `disk_count` in declared
      order; the assignment summary is rendered and confirmed before
      accept.
- [x] bats: skeleton-from-choices + validation reuse.
- [x] VM smoke: a multi-disk guided install (mirror OS + raidz1 storage)
      boots. (Install INSTALLER-EXIT-0; boots to ===FIRSTBOOT-OK=== —
      confirmed via manual disk boot; automated --verify-boot is flaky for
      multi, a harness gap, see Comments.)

## Blocked by

- `01-guided-install-tracer-bullet`

## Comments

**Presets + multi VM DONE via /tdd (2026-06-17); Advanced authoring deferred
(user-approved scope split).**

Pure core `lib/config/skeleton.sh`: `skeleton_preset` (single / os-mirror /
os-mirror-raidz1 / data-pools → device-less os_pool/storage_groups/data_pools
with topology+disk_count), `skeleton_total_disks`, `skeleton_validate`
(reuses picker `_picker_validate_group` so the min-disk table never drifts;
names an under-populated group), `skeleton_assignment_summary`. 13 bats
(`tests/config/guided-skeleton.bats`).

Guided shell (`lib/guided.sh`): `_guided_edit_layout` (preset → skeleton
merged into Config State, replacing any prior), `guided_pick_disks <key> <n>`
(N-disk seam; replay = whitespace list, interactive = fzf multi-select),
`_guided_resolve_assignment` (multi → picker_build_assignment slices Σ
disk_count per group → skeleton_assignment_summary → typed ACCEPT gate),
loop layout row + multi-aware Proceed. guided-shell +6 bats.

VM: `vm/lib/seed-generator.sh` renderer + `vm/lib/flow-guided.sh` drive a
multi preset (resolve N disks in-guest, replay layout/disks/accept_layout);
`tests/vm/profiles/single/guided-multi.jsonc` (os-mirror-raidz1, 5 disks).
VM run: guided replay → per-group summary (OS pool mirror 2 disks, storage
data raidz1 3 disks) → **rpool mirror + dpool raidz1 created → INSTALLER-EXIT-0**;
the installed system **boots to ===FIRSTBOOT-OK===** (verified by booting the
disk manually). Full suite **1149 bats**, shellcheck clean.

**Harness gap (not a guided bug):** automated `--verify-boot` flaked for the
multi VM (empty serial log + ~67s poweroff — the first post-install boot
appears to re-enter the install ISO). Every existing `multi/` profile has
`verify.boot` unset, so multi boot-verify was never exercised; worth a
separate harness fix (CDROM eject / boot-order on first post-install boot).
