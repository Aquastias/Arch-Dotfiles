# Migration tracer: equivalence test + migrate arch-data

Status: ready-for-human

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

- [x] An equivalence test asserts legacy synthesis == hand-written
      `profile.jsonc` for a host.
- [x] `hosts/vm/arch-data/profile.jsonc` replaces its `config.jsonc`.
- [ ] `arch-data` installs via `--profile arch-data` (or a VM run).
- [x] Equivalence test green for `arch-data`; all suites green.

## Blocked by

- `.scratch/unified-host-profile/issues/01-profile-loader-schema-assembler.md`

## Comments

### Agent (TDD)

Design B: a complete `profile.jsonc` (machine skeleton minus devices +
software), so the profile fully describes the machine.

- `hosts/core/profile.jsonc` mirrors the core software base; coexists
  with the legacy core files during migration (both produce the same
  base).
- `hosts/vm/arch-data/profile.jsonc` carries system/options + the pool
  skeleton (os_pool topology none; data_pools tank0 stripe / tank1
  mirror) with no device fields; `config.jsonc` removed.
- `load_profile` gained the `hosts/vm/<name>/` real-path fallback
  (mirrors `_configs_load`), so VM hosts resolve their `profile.jsonc`.
- Equivalence guard (`tests/config/profile-loader.bats`): `load_profile
  arch-data` preserves the legacy software synthesis ({sysctl,
  system_programs:[cups], users:[vm-data]}) and adds the skeleton; no
  `host_profile`; validates closed-schema. Plus a VM real-merge unit.

Full suite green (1038/1038). `--profile arch-data --print-config`
emits the correct skeleton.

AC3 (actual install) is the VM gate: arch-data's data pools need
per-group disk assignment, which the interactive picker defers to the
VM harness rewire (issue 07). Hence `ready-for-human`.
