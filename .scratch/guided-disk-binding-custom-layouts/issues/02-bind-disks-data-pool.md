# 02 — Bind real disks to a data pool (device-mode tracer)

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/guided-disk-binding-custom-layouts/PRD.md`

## What to build

The first complete vertical slice of **In-Menu Disk Binding**: on a machine with
real disks, an operator opens a standalone data pool and binds/unbinds actual
`/dev/disk/by-id/*` devices, and the pool's disk count reflects exactly what they
chose — so over-declaring is impossible. Off-target (no disks), the pool keeps
today's abstract `disk_count` cycle untouched.

Behavior:

- **On-target detection** — device-mode iff the disk enumerator returns ≥1
  candidate (live medium excluded), evaluated once at guided launch and cached.
- **Pool data model** — a pool gains an additive optional `devices[]` of full
  by-id paths; when present `disk_count` is derived as its length.
- **Disk sub-screen** — the data pool's `disks:` row opens an Enter-toggle
  multi-select over `bound ∪ free` disks (bound = marked); Enter binds/unbinds;
  Esc backs out. Each row shows `<size> <model> · <by-id-tail>`.
- **Free Set** — enumerated candidates minus the live medium minus every disk
  already bound to any group; the sub-screen offers only free (unmarked) + bound
  (marked) disks, so an exhausted set simply shows no unmarked rows.
- **Filesystem-pin trim** — cycling the pool's filesystem to ext4/xfs trims
  `devices[]` to the first entry, returning the rest to the Free Set.

Count-mode (off-target) is unchanged; this slice does not touch the OS pool,
storage groups, single-disk root, install/flatten, or chrome.

## Acceptance criteria

- [ ] With a faked by-id dir (`PICKER_BY_ID_DIR`) holding disks, launch enters
      device-mode; with none, count-mode — asserted at the pure seam.
- [ ] Binding a disk adds its by-id path to the pool's `devices[]`; unbinding
      removes it; `disk_count` equals the number bound (pure seam).
- [ ] The Free Set excludes the live medium and any disk already bound to another
      group; a bound disk never appears as free for a second pool.
- [ ] The disk sub-screen renders bound disks marked + free disks unmarked with
      `<size> <model> · <tail>` labels, and Enter emits the toggle reload-sync
      action (fzf-entry seam), with the nav file entering/leaving the sub-screen.
- [ ] Cycling the pool to ext4/xfs leaves exactly the first bound disk and frees
      the rest (pure seam).
- [ ] Off-target, the data-pool `disks:` row still shows the 1–8 count cycle.
- [ ] Full existing bats suite stays green.

## Blocked by

- 01 — Prefactor: address pool groups by (kind, index).
