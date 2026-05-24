Status: done

# Relocate fixture program to .os/tests/fixtures/programs/hello/

## Parent

`.scratch/config-generator-finalization/PRD.md`

## What to build

`programs/_fixture/hello/` exists in the production tree solely
because the slice-01 e2e acceptance criterion exercises the real
CLI walking the real `programs/` root. Every installed host
inherits a permanent `~/.config/hello/greeting` artifact for no
operational reason.

Move the fixture to `.os/tests/fixtures/programs/hello/` so
production trees ship no fixture program. The Config Generator
CLI already accepts a `PROGRAMS_ROOT` env override (used by
existing slice-06 bats); bats files use that override to point at
the new location.

After this slice, no production tree contains a `_fixture/`
directory.

## Acceptance criteria

- [ ] `.os/programs/_fixture/` no longer exists
- [ ] `.os/tests/fixtures/programs/hello/configs/manifest.jsonc`
      exists with the same contents as the previous fixture
- [ ] All bats that referenced the old fixture path use the new
      one (via `PROGRAMS_ROOT` override where applicable)
- [ ] `tests/run.sh` still passes
- [ ] `tests/audit.sh` still passes
- [ ] A clean fresh install does not produce
      `~/.config/hello/greeting`

## Blocked by

None — can start immediately.
