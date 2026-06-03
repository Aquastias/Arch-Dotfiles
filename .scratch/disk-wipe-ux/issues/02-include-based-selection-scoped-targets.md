# Include-based selection + install-driven scoped targets

Status: ready-for-agent

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

- [ ] Standalone, nothing is wiped unless disks are explicitly selected
      (Enter cancels).
- [ ] A single disk can be selected and wiped without affecting others.
- [ ] An install (interactive or unattended) wipes only its target
      disks; unrelated data disks are untouched.
- [ ] The Single Entry Point resolves and passes the target list; the
      wipe receives it explicitly.
- [ ] Selection / target-resolution logic is unit-tested (include
      parsing, default-cancel, scoped target set).

## Blocked by

- `issues/01-live-medium-exclusion.md`
