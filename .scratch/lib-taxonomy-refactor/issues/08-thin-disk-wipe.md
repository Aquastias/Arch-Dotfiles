Status: done

# Thin the Disk Wipe: extract pure prior-state, orchestrator 02-wipe.sh

## Parent

`.scratch/lib-taxonomy-refactor/PRD.md`

## What to build

Move the device-aware Disk Wipe logic out of `02-wipe.sh` into the
`lib/wipe/` module and reduce `02-wipe.sh` to a thin orchestrator that
calls the module. Extract the "is this target disk already zeroed vs.
carries signatures" decision into a new **pure** module
`lib/wipe/prior-state.sh` that operates over probed disk facts and
returns the set to wipe.

Both Disk Wipe safety invariants must be preserved exactly:

- The live medium is never listed, selectable, or wipeable — detected by
  multiple signals (boot-mount parent disk, `iso9660` / `ARCH_*` label),
  never by string-matching.
- An install-driven wipe touches only the install's resolved target set
  (`os_pool` + `storage_groups` + `data_pools` disks resolved from the
  Install Config and passed in explicitly), never an unrelated disk.

Method remains device-aware (blkdiscard on SSD/NVMe, single zero-pass on
HDD with per-disk parallel progress). Multi-pass/forensic erase stays
out of scope. Add an ADR for the Disk Wipe module extraction.

## Acceptance criteria

- [ ] `lib/wipe/prior-state.sh` is a pure function over probed disk
      facts returning the set to wipe (no block-device I/O)
- [ ] `02-wipe.sh` is a thin orchestrator; device-aware logic lives in
      `lib/wipe/`
- [ ] Live-medium exclusion preserved (multi-signal, not string match)
- [ ] Install-driven wipe touches only the resolved target set
- [ ] Pure tests: no-signature disk → already-blank; ZFS/LVM/MD label or
      partition table → needs-wipe; resolved target set excludes the
      live medium
- [ ] VM smoke tests still cover the real wipe path
- [ ] ADR added for the Disk Wipe module extraction

## Blocked by

- Issue 04 (`04-wipe-folder-move.md`) — `lib/wipe/` must exist first
