# Migration tracer: equivalence test + migrate arch-data

Status: ready-for-agent

## Parent

`.scratch/unified-host-profile/PRD.md`

## What to build

Prove the whole migration path on the smallest host. Add an equivalence
test asserting that the legacy synthesis (template + config through the
assembler) produces the same effective config as a hand-written
`profile.jsonc` for a given host. Then migrate `arch-data` first — the
template-less VM host — by writing `hosts/vm/arch-data/profile.jsonc` and
removing its `config.jsonc`. This is the tracer that de-risks the bulk
migration.

## Acceptance criteria

- [ ] An equivalence test asserts legacy synthesis == hand-written
      `profile.jsonc` for a host.
- [ ] `hosts/vm/arch-data/profile.jsonc` replaces its `config.jsonc`.
- [ ] `arch-data` installs via `--profile arch-data` (or a VM run).
- [ ] Equivalence test green for `arch-data`; all suites green.

## Blocked by

- `.scratch/unified-host-profile/issues/01-profile-loader-schema-assembler.md`
