# Include-based selection + install-driven scoped targets

Status: done

## Parent

`.scratch/disk-wipe-ux/PRD.md`

## What to build

Flip the wipe's selection model. Run standalone, the wipe shows the
(live-medium-excluded) disk table and asks which disk(s) to wipe —
entering indices or `all`, with Enter cancelling and the default being
to wipe nothing. Run as part of an install, the Single Entry Point
resolves the install's target disks (from `os_pool` + `storage_groups` +
`data_pools`) and passes them to the wipe as an explicit list, so the
wipe only ever touches disks the install will use and stays
config-agnostic itself. A clear final confirmation precedes any
destructive action.

## Acceptance criteria

- [x] Standalone, nothing is wiped unless disks are explicitly selected
      (Enter cancels).
- [x] A single disk can be selected and wiped without affecting others.
- [x] An install (interactive or unattended) wipes only its target
      disks; unrelated data disks are untouched.
- [x] The Single Entry Point resolves and passes the target list; the
      wipe receives it explicitly.
- [x] Selection / target-resolution logic is unit-tested (include
      parsing, default-cancel, scoped target set).

## Blocked by

- `issues/01-live-medium-exclusion.md`

## Comments

- Implemented (TDD). Two pure cores + thin wiring:
  - `lib/wipe-targets.sh` — Target Resolver `wipe_resolve_targets
    <config>`: unions single `.disk` + `os_pool.disks` +
    `storage_groups[].disks` + `data_pools[].disks`, deduped (`unique`).
    5 `wipe-targets.bats` cases (single, multi, union, dedup, empty).
  - `02-wipe.sh` `parse_disk_selection INPUT DISK…` — include-based:
    empty→nothing (default-cancel), `all` (case-insensitive)→every disk,
    else 1-based indices with garbage/out-of-range skipped and result
    deduped (no double-wipe). `select_disks` is now a thin prompt over
    it. 6 `wipe-select.bats` cases + 2 for `parse_args` capturing
    positional DISKs into `TARGETS` (with `-y`).
- Wiring (decisions: positional handoff; unattended-no-target = no-op):
  - `02-wipe.sh` takes positional DISK paths as explicit `TARGETS`;
    `main` branches — targets→wipe exactly those (skip detect+select);
    unattended+no targets→`info "Nothing to wipe"; exit 0`; else
    interactive detect+include-select. The live-medium hard guard,
    already-zeroed skip, and both confirmations still run on the chosen
    set.
  - `install.sh` (Single Entry Point) resolves targets from the config
    (path mirrors `03-install.sh`) and forwards them as positional disks
    to `02-wipe.sh`, so the wipe stays config-agnostic and only ever
    touches the install's disks.
- Full bats green (13 new; 895→908; the 7 `layout-multi` data-pool
  failures are pre-existing on this host — they need real block
  devices/root, confirmed by `git stash`). `shellcheck.sh` clean.
  CONTEXT.md "Disk Wipe" already described this model (PRD-era) — no
  change needed.
- Not exercised here: the actual destructive multi-disk install run
  ("unrelated data disks untouched" end-to-end) — structurally
  guaranteed (only `TARGETS` ever reach `DISKS_TO_WIPE`) and covered by
  the existing VM smoke tests; no libvirt on this dev host. Same bar as
  sibling slices 01/03/04 (unit-tested wipe logic = done).
