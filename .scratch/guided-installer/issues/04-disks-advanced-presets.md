# Disks: multi-disk presets + Advanced skeleton authoring

Status: done


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
      `os_pool` / `storage_groups` / `data_pools`.
- [x] The skeleton builder agrees with `picker_validate_layout` and the
      min-disk table; an under-populated group is named in the error.
- [x] Picked disks are sliced per-group by `disk_count` in declared
      order; the assignment summary is rendered and confirmed before
      accept.
- [x] bats: skeleton-from-choices + validation reuse.
- [x] VM smoke: a multi-disk guided install (mirror OS + raidz1 storage)
      boots. (`--verify-boot`: INSTALLER-EXIT-0 → ===FIRSTBOOT-OK===, after
      the multi-disk console-capture harness fix; see Comments.)

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

**Advanced authoring (follow-up, now DONE):** composable builders
`skeleton_new_multi` / `skeleton_add_storage` / `skeleton_add_data_pool`
(owners → array) in `skeleton.sh`; `_guided_author_skeleton` (guided.sh) walks
OS pool → N storage groups → N data pools through the seam (replay-driven keyed
answers `adv_*`), guards with `skeleton_validate`, applies via
`_guided_apply_skeleton`; wired as the `advanced` layout choice. +7 bats.

**Multi boot-verify harness fix (follow-up, now DONE):** the automated
`--verify-boot` failure was NOT ISO re-entry — the boot-verify **console
capture died mid-boot** (the serial PTY drops on the slower multi-disk boot,
when the kernel then serial-getty re-grab the console), so the first-boot
marker printed afterwards was lost (VM booted fine; log stayed empty).
`flow-test.sh` now **re-attaches `virsh console` (append) until the domain
halts** (`_console_capture_loop`), making boot-verify robust for multi-disk.
Re-run of `single/guided-multi --verify-boot`: **INSTALLER-EXIT-0 →
===FIRSTBOOT-OK===** (automated). +2 bats (`tests/vm/console-capture.bats`).
Full suite **1158 bats**, shellcheck clean.
