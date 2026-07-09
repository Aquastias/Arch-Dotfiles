# 01 — Prefactor: address pool groups by (kind, index)

Status: done
Type: AFK

## Parent

`.scratch/guided-disk-binding-custom-layouts/PRD.md`

## What to build

A pure, behavior-preserving prefactor so the pool editor can target **any** pool
group — the OS pool (a singleton object), a storage group, or a standalone data
pool — through one uniform reference, instead of the current integer index into
`data_pools[]` only. This unblocks binding and editing the OS pool and storage
groups in later slices without reworking the nav model then.

Introduce a group reference of `(kind, index)` where `kind ∈ {os, storage,
data}` (index unused for `os`) threaded through the editor's nav state and enter
dispatch. The existing data-pool editor keeps working exactly as today — same
screens, same rows, same mutations — it just reaches `data_pools[i]` via the new
reference. No new user-visible behavior; the whole point is that nothing changes
on screen and every test stays green.

## Acceptance criteria

- [x] The pool-editor nav state carries a group reference of `(kind, index)`;
      `data` behaves identically to today's index-only addressing.
- [x] Enter dispatch on the pool editor resolves the group through the reference,
      not a bare `data_pools[$i]` lookup.
- [x] No change to any rendered list, header, prompt, or mutation for the
      existing data-pools flow (pure refactor).
- [x] `os` and `storage` reference kinds resolve to the right skeleton object
      (unit-tested), even though no UI reaches them yet.
- [x] Full existing bats suite stays green.

## Blocked by

- None — can start immediately.
