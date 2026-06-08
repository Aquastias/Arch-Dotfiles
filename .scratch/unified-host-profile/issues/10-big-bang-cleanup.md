# Big-bang cleanup

Status: ready-for-agent

## Parent

`.scratch/unified-host-profile/PRD.md`

## What to build

Reach the no-shim end state. With every host/user on `profile.jsonc`,
delete the legacy host `config.jsonc` + `install.template.jsonc` (programs
keep `config.jsonc`), delete the root `install.jsonc`, and remove the
transient assembler + legacy readers + the equivalence test so
`load_profile` reads only `profile.jsonc`. Relocate the root config's
single / multi / data_pools example blocks to the schema reference
(`REFERENCE.md` / `ARCHITECTURE.md`).

## Acceptance criteria

- [ ] Legacy host `config.jsonc` + `install.template.jsonc` removed;
      programs keep `config.jsonc`.
- [ ] Root `install.jsonc` deleted; its example blocks relocated to the
      schema reference.
- [ ] Transient assembler + legacy readers + equivalence test removed;
      `load_profile` reads only `profile.jsonc`.
- [ ] No dual-read remains; all suites green.

## Blocked by

- `.scratch/unified-host-profile/issues/09-migrate-remaining-configs.md`
- `.scratch/unified-host-profile/issues/07-vm-harness-rewire.md`
