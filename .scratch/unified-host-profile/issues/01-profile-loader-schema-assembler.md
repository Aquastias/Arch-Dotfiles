# Profile Loader + closed schema + transient assembler

Status: ready-for-agent

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

- [ ] `load_profile <name>` merges host profile + host core (and user
      profile + user core) into an effective config from a real
      `profile.jsonc` when present.
- [ ] With no `profile.jsonc`, it synthesizes the same effective config
      from legacy `install.template.jsonc` + `config.jsonc` via the
      existing assembler.
- [ ] The schema enumerates every currently-valid key (the union of
      legacy `install.jsonc` + host/user `config.jsonc`), driving reads +
      defaults.
- [ ] Unknown keys at any depth (nested + arrays-of-objects) in host
      profile+core, user profile+core, and program `config.jsonc` abort
      with the offending path, before any disk write.
- [ ] A typo'd program `system` key is caught.
- [ ] `install.sh --profile <name> --print-config` validates, assembles,
      and emits the effective config to stdout (no libvirt, no writes).
- [ ] bats: Profile Loader + schema (merge, defaults, recursive
      rejection) green; existing suites stay green.

## Blocked by

- None - can start immediately.
