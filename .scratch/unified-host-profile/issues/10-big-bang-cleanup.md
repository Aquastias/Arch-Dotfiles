# Big-bang cleanup

Status: done

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

- [x] Legacy host `config.jsonc` + `install.template.jsonc` removed;
      programs keep `config.jsonc`.
- [x] Root `install.jsonc` deleted; its example blocks relocated to the
      schema reference.
- [x] Transient assembler + legacy readers + equivalence test removed;
      `load_profile` reads only `profile.jsonc`.
- [x] No dual-read remains; all suites green.

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

### Agent note (Claude) — 2026-06-12 — DONE

No-shim end state reached. TDD slices, all suites green throughout.

**Loader.** `profile.sh`: dropped `_load_profile_synthesize` + the user
fallback; `load_profile`/`load_user_profile` now share `_profile_load`
reading only `profile.jsonc` with the same `0/1/2/3` contract the old
readers had — so consumers migrated by a name-swap.

**Consumers migrated** (`load_host_config`→`load_profile`,
`load_user_config`→`load_user_profile`, `config.jsonc`→`profile.jsonc`
guards): `install-state`, `secrets`, `runner` (+core guards & user
load), `validation` (preflight guards + 3 loaders), `packages/list`,
`pool-owners._pool_owners_group_map`, `tools/generate-configs`,
`tools/impermanence` (persist writers → `profile.jsonc`). `03-install.sh`
now sources `profile.sh`. `generate-configs` dropped its `install.jsonc`
host-profile read (dir≡hostname).

**Legacy readers removed** from `layers.sh` (`_configs_load`/
`load_host_config`/`load_user_config`); parse/merge/registry/program
helpers stay.

**Files deleted.** 11 host `config.jsonc` + 7 `install.template.jsonc`,
root `install.jsonc`, 4 user `config.jsonc`, 3 fixture `config.jsonc`.
Programs keep `config.jsonc`.

**pick.sh retired** (operator decision): deleted `tools/pick.sh` +
`picker_enum_hosts`/`load_template`/`pin_from_template`/`assemble_config`/
`parse_choice`/`render_review`; trimmed `picker.bats`; `install.sh
--profile` is the only interactive path. README install flow rewritten.

**Tests.** Deleted equivalence test `profile-migration.bats`; rewrote
`configs.bats` (real-profile invariants + program resolution; loader
contract moved to `profile-loader.bats`); migrated vm/impermanence/aur
fixtures to `profile.jsonc`. Fixed an audit vacuous-pass: checks 8/10/11/
14 read host/user `config.jsonc` → now `profile.jsonc` (56→82 real
checks).

**Docs.** `install.jsonc` single/multi/data_pools examples relocated to
`REFERENCE.md` § Profile Layout Examples (device-free skeletons, ADR
0037); dead `install.template.jsonc Reference` section removed; schema
header → Host Profile Reference. ARCHITECTURE.md diagrams + CONTEXT.md
glossary stay issue 11.

**Verify.** 1007 bats pass (0 fail); `audit.sh` 82 checks pass;
shellcheck clean (one pre-existing `CONFIG_FILE` SC2153 info).
