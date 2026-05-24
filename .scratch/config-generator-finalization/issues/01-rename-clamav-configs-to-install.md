Status: done

# Rename clamav configs/ → install/

## Parent

`.scratch/config-generator-finalization/PRD.md`

## What to build

Atomic per-program rename of the install-side scaffolding
directory for `clamav`. Per ADR 0013, `configs/` is reserved for
the Program Config Tree (ADR 0012). The directory under
`programs/security/clamav/` that holds `clamd.conf`,
`freshclam.conf`, `user.conf` is install-side input consumed by
the program's `install.sh` — not a Program Config Tree — so it
moves to `install/`.

Edit clamav's `install.sh` so any path that referenced the old
directory now points at the new one. Verify by re-reading the
install script end-to-end — there should be no stale references.

This slice does not change Config Generator behavior. It is a
prerequisite for the resolver gate change (slice 03).

## Acceptance criteria

- [ ] `programs/security/clamav/configs/` no longer exists
- [ ] `programs/security/clamav/install/` exists with the same
      file contents as the previous `configs/`
- [ ] `programs/security/clamav/install.sh` references
      `install/` (no remaining `configs/` references)
- [ ] `tests/audit.sh` still passes
- [ ] `tests/run.sh` still passes
- [ ] One commit, scoped to clamav only

## Blocked by

None — can start immediately.
