# Default data-pool ownership → Primary User + ~/Disks symlinks

Status: done

## Parent

`.scratch/pool-owners-access/PRD.md`

## What to build

A new install step, run inside the chroot after the Runner has created
users and groups (and while the pools are mounted under the altroot),
that makes every data-pool mountpoint usable by a human. For each
Combined Data Pool dataset (per Storage Group) and each Standalone Data
Pool, it gives ownership to the Primary User and creates a
`~/Disks/<pool>` symlink in that user's home so the pool is reachable
from any file manager — GUI or TUI. This slice stands up the **Owners
Resolver** in its simplest form (the plain-`chown` path) plus the
applier and the end-to-end integration. When the host declares no users
(no Primary User), the mountpoint is left `root`-owned and a warning is
emitted rather than failing the install.

## Acceptance criteria

- [x] After install, each data-pool mountpoint is owned by the Primary
      User and writable by them without `sudo`.
- [x] Each owned pool appears as `~/Disks/<pool>` in the Primary User's
      home and resolves to the mountpoint.
- [x] Both Combined Data Pool (Storage Group) datasets and Standalone
      Data Pools are covered.
- [x] On a host with no declared users, pools are left `root`-owned and
      a warning is logged; the install still succeeds.
- [x] The Owners Resolver's chown-path decision is unit-tested (omitted
      owners → Primary User; userless host → no-op + reason).
- [ ] The multi-data-pools VM smoke test asserts a pool is owned and
      writable by its owner on the booted system.

## Blocked by

None - can start immediately.

## Comments

- 2026-09-27 audit: fd1f5ac, c00705d. Remaining unticked lines are suite/VM runs
  not re-verifiable now.
