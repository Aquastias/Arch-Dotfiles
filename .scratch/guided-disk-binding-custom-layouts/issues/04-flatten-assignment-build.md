# 04 — Flatten + assignment build (a bound layout installs)

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/guided-disk-binding-custom-layouts/PRD.md`

## What to build

Make a bound layout actually terminal: Save keeps the profile device-less, and
Proceed/Export turn the bound disks into an Effective Config — so the disks an
operator chose in the menu drive the real install, while the committed profile
stays portable.

- **Save** — flatten every group's `devices[]` back to `disk_count` = number
  bound and drop `devices`, so the saved Host Profile is device-less (ADR 0036).
- **Proceed / Export** — lift each group's `devices[]` out of the skeleton into
  the per-group **assignment JSON** (`{os_pool:[…], storage_groups:[[…]],
  data_pools:[[…]]}`, the shape `picker_assign_disks` consumes), and hand a
  device-less skeleton to the Effective Config emitter. The bound on-target path
  replaces the post-menu flat-slice + ACCEPT prompt.
- **Convergence** — the assignment built from `devices[]` for a set of disks must
  equal what the post-menu `picker_build_assignment` produces for the same disks
  in the same order, so both paths yield an identical Effective Config.
- **Mixed layouts** — a layout with some counted groups (e.g. authored partly
  off-target) still runs the flat pick for the counted remainder.
- `devices[]` never appears in any schema-validated artifact.

## Acceptance criteria

- [ ] Save on a bound layout writes a profile with `disk_count` per group and no
      `devices` key (pure seam).
- [ ] Proceed/Export build a per-group assignment JSON from `devices[]` and emit a
      valid Effective Config through the existing emitter (pure seam).
- [ ] The `devices[]`-built assignment equals `picker_build_assignment`'s output
      for the same disks — equivalence pinned by a test (pure seam).
- [ ] A fully-bound layout runs no post-menu flat pick and no ACCEPT prompt; a
      partially-counted layout flat-picks only the counted groups.
- [ ] An under-populated bound pool (e.g. mirror with one disk) is rejected by
      the existing skeleton validation naming the group.
- [ ] Full existing bats suite stays green.

## Blocked by

- 03 — Bind-all: OS pool, storage groups, single-disk root.
