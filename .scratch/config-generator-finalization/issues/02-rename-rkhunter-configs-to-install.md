Status: ready-for-agent

# Rename rkhunter configs/ → install/

## Parent

`.scratch/config-generator-finalization/PRD.md`

## What to build

Atomic per-program rename of the install-side scaffolding
directory for `rkhunter`. Same shape as the `clamav` rename
(slice 01) and same rationale: `configs/` is reserved for the
Program Config Tree per ADR 0013.

The directory under `programs/security/rkhunter/` that holds
`rkhunter.conf` moves to `install/`. Edit `install.sh` so any
path that referenced the old directory now points at the new
one.

This slice does not change Config Generator behavior. It is a
prerequisite for the resolver gate change (slice 03).

## Acceptance criteria

- [ ] `programs/security/rkhunter/configs/` no longer exists
- [ ] `programs/security/rkhunter/install/` exists with the same
      file contents as the previous `configs/`
- [ ] `programs/security/rkhunter/install.sh` references
      `install/` (no remaining `configs/` references)
- [ ] `tests/audit.sh` still passes
- [ ] `tests/run.sh` still passes
- [ ] One commit, scoped to rkhunter only

## Blocked by

None — can start immediately.
