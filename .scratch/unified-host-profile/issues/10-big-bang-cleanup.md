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

## Comments

### Agent note (Claude) — 2026-06-10

Heads-up before deleting legacy readers: the **host-side** read was a
live trap. The Profiles Runner (`runner.sh`), pool-owners
(`pool-owners.sh`), and validation preflight read the host via
`load_host_config $RESOLVED_HOST_PROFILE` (legacy `config.jsonc`). With
`config.jsonc` deleted, that returns `rc=1` → the Runner *skips entirely*.
The Runner + `_pool_owners_declared_users` are now repointed at the
assembled effective `$CONFIG_FILE` (done while verifying issue 08), so the
*host* side no longer depends on `config.jsonc`.

**Still legacy-bound (must be handled here):**
- `runner.sh` loads each user via `load_user_config "$u"` (user
  `config.jsonc`); `_pool_owners_group_map` does too. Deleting user
  `config.jsonc` will break these — migrate to the user `profile.jsonc`
  loader.
- `validation.sh:_validation_preflight_programs` + `run_profiles` still
  guard on `hosts/core/config.jsonc` / `users/core/config.jsonc`
  existence — remove those guards when the files go.
- Gap #5 (per-group data-pool disk assignment + picker/layout min-disk
  reconciliation, see issue 08) is independent but blocks arch-data's
  `--profile` install.
