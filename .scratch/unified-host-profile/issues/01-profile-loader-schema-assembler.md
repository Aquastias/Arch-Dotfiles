# Profile Loader + closed schema + transient assembler

Status: done

## Parent

`.scratch/unified-host-profile/PRD.md`

## What to build

The pure spine of the redesign: read a unified Host Profile and turn it
into an effective install config, with up-front closed-schema
validation — all without libvirt or disk writes.

`load_profile <name>` merges the host profile with host core (and an
analogous path merges user profile + user core) into the effective
config. When a real `profile.jsonc` is absent, it synthesizes the same
effective config from the legacy `install.template.jsonc` + `config.jsonc`
through the existing picker assembler — the transient scaffold that lets
every later slice stay green while legacy files still exist.

The existing `_INSTALL_CONFIG_SCHEMA` (ADR 0015) is completed into the
single authoritative table that enumerates every currently-valid key
across the legacy `install.jsonc` and host/user `config.jsonc` (their
union), driving reads, defaults, AND recursive unknown-key rejection. Any
unknown key at any depth — nested objects and arrays-of-objects like
`storage_groups[]` — aborts with the offending path, before any
disk-touching phase. Validation covers host profile + core, user profile
+ core, and program `config.jsonc`.

`install.sh --profile <name> --print-config` exercises this end-to-end:
validate + assemble + emit the effective config to stdout.

## Acceptance criteria

- [x] `load_profile <name>` merges host profile + host core (and user
      profile + user core) into an effective config from a real
      `profile.jsonc` when present.
- [x] With no `profile.jsonc`, it synthesizes the same effective config
      from legacy `install.template.jsonc` + `config.jsonc` via the
      existing assembler.
- [x] The schema enumerates every currently-valid key (the union of
      legacy `install.jsonc` + host/user `config.jsonc`), driving reads +
      defaults.
- [x] Unknown keys at any depth (nested + arrays-of-objects) in host
      profile+core, user profile+core, and program `config.jsonc` abort
      with the offending path, before any disk write.
- [x] A typo'd program `system` key is caught.
- [x] `install.sh --profile <name> --print-config` validates, assembles,
      and emits the effective config to stdout (no libvirt, no writes).
- [x] bats: Profile Loader + schema (merge, defaults, recursive
      rejection) green; existing suites stay green.

## Comments

Implemented via TDD (10 vertical slices). New deep module
`.os/lib/config/profile.sh`: `load_profile` / `load_user_profile` (real
`profile.jsonc` + core merge, else transient synthesis from legacy
template+config), `validate_config_schema {host,user,program}` (jq-based
recursive closed-schema rejection reporting the shortest offending path),
and `validate_profile` (validate-at-load aggregator over host + referenced
users + referenced program configs). `install.sh` gains `--profile` +
`--print-config` (short-circuits before any disk phase).

Schema/reads single-source kept honest by a drift-guard test asserting
every `_INSTALL_CONFIG_SCHEMA` read-path is a valid key; completeness
forced by tests that validate every real host/user/program config clean.

Tests: `.os/tests/config/profile-loader.bats` (22) +
`install-print-config.bats` (3). Full suite green (988).

Note: locale/keymap stay scalar here; the array form + interactive
`--profile` (picker→disks) land in the later slices (04 / 03).

## Blocked by

- None - can start immediately.
