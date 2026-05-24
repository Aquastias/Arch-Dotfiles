Status: needs-triage

# Audit: assert no _fixture/ under .os/programs/

## Parent

`.scratch/config-generator-finalization/PRD.md`

## What to build

After slice 04 relocated `programs/_fixture/hello/` to
`.os/tests/fixtures/programs/hello/`, the absence of any
`_fixture/` under `.os/programs/` is a convention — not enforced.
A future contributor (or sloppy revert) could re-introduce a
production fixture program without any test catching it.

Add a single check in `tests/audit.sh` that fails loudly if any
`_fixture/` directory exists under `.os/programs/`. The check
costs ~one find invocation and locks in the ADR 0013 +
slice-04 contract that production trees ship no fixture.

## Acceptance criteria

- [ ] `tests/audit.sh` fails when any `_fixture/` exists under
      `.os/programs/`
- [ ] Check passes on `main` as-is (post slice 04)
- [ ] One commit, scoped to `audit.sh` only

## Blocked by

Slice 04 (relocate fixture) — already merged.
