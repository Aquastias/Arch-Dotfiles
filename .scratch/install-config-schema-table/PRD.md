Status: ready-for-agent

# PRD: Install Config schema-driven accessors

References: ADR 0015.

## Problem Statement

`lib/install-config.sh` exposes ~25 typed accessors for the
Install Config — `install_config_kernel`,
`install_config_bootloader`, `install_config_swap_enabled`, and so
on. Each is a 2–3 line wrapper around `cfgo` or `jsonc_read` with
an inline default. The Install Config schema (paths + defaults) is
implicit across 25 function bodies; defaults drift; a schema change
requires touching the default in multiple places; tests are written
per-accessor (60+ cases for the same shape). The repo already
proved a better pattern in `lib/install-state.sh`, where
`_INSTALL_STATE_SCHEMA` is the single source of truth for the
install-state wire format.

## Solution

Declare the Install Config schema as a single pipe-delimited array
at the top of `lib/install-config.sh`. A single
`install_config_get <name>` dispatches on the schema entry's type
and applies its default. The 21 regular named wrappers are
generated from the schema at source time so call sites and grep
behaviour stay unchanged. Four specials stay hand-written below
the schema. Tests collapse to a parameterised loop over the schema
plus dedicated cases for the four specials and the bool
null-distinction.

## User Stories

1. As the installer maintainer, I want to declare a new Install
   Config field by adding one row to the schema table, so that
   path + default + type live in one place instead of three.
2. As the installer maintainer, I want defaults to live in exactly
   one place, so that they cannot drift between the function body
   and the documentation.
3. As the installer maintainer, I want adding a field to require
   updating one place, not two (function + test), so that the
   per-accessor boilerplate vanishes.
4. As a caller of `install_config_kernel` or
   `install_config_bootloader`, I want every existing accessor
   name to keep working, so that nothing changes for me.
5. As a future engineer reading the schema, I want one glance at
   `_INSTALL_CONFIG_SCHEMA` to tell me every Install Config field,
   its jq path, its type, and its default, so that I do not have
   to read 25 function bodies to learn the shape of the config.
6. As an installer-test author, I want one parameterised test
   that iterates the schema asserting default-on-absent and
   value-on-present for every entry, so that adding a field does
   not require writing two more test cases.
7. As a developer debugging a wrong default, I want
   `grep install_config_kernel` to land on the schema row that
   declares the kernel default, so that the canonical declaration
   is the first thing I see.
8. As the installer maintainer, I want the four genuinely-special
   accessors (custom jq filter, positional index argument,
   string|array union with default) to stay hand-written, so that
   real exceptions are visible as exceptions instead of hiding in
   schema soup.
9. As an installer running on the live CD, I want every accessor
   to produce identical output to today's behaviour for the same
   input, so that nothing observable changes from the operator's
   perspective.
10. As a future engineer wondering "where is
    `install_config_kernel` defined?", I want a short comment at
    the top of the file pointing at the eval loop, so that the
    indirection is discoverable.
11. As a bash maintainer, I want `install_config_get` itself to
    be statically defined (not generated), so that shellcheck
    sees the shared body and can catch real bugs.

## Implementation Decisions

- **Schema table**: a single bash array
  `_INSTALL_CONFIG_SCHEMA` at the top of the module. Each entry
  is pipe-delimited as `name|jq_path|type|default`. Type is one
  of `scalar`, `bool`, `array`. An empty default field is
  semantically "no default" — the accessor emits an empty string
  when the path is absent, matching today's behaviour for
  `hostname`, `age_key_url`, `dotfiles_repo`.
- **Coverage**: the schema covers 21 of today's accessors. The
  four specials (`install_config_packages_groups`,
  `install_config_storage_group_ashift`,
  `install_config_gpu`, and the `_install_config_array` helper)
  stay hand-written below the schema.
- **Core function**: `install_config_get <name>` looks up the
  schema row by name and dispatches on type:
  - `scalar` uses `cfgo` (jq with `// empty`)
  - `bool` uses `jsonc_read` and distinguishes literal `null`
    from `false` (preserving today's bool-safe behaviour)
  - `array` uses the `_install_config_array` helper
  After reading the value it applies the schema default.
- **Generation**: a `for spec in "${_INSTALL_CONFIG_SCHEMA[@]}";
  do … eval "install_config_${name}() { install_config_get
  ${name}; }"; done` loop runs at source time. Each wrapper is
  one line and forwards by name to `install_config_get`.
- **Trade-off acknowledged**: generated wrappers are invisible to
  shellcheck and to `grep install_config_kernel`. The schema row
  is greppable, and a comment above the eval loop tells future
  readers where to look. `install_config_get`'s body is
  statically visible and shellcheck-checked.
- **Behaviour parity**: every wrapper produces identical output
  to today's hand-written body for the same input. This includes
  the bool null-distinction (`null` and absent map to the
  default; literal `false` does not).
- **The four specials**, unchanged in behaviour:
  - `install_config_packages_groups` — custom jq filter, not a
    simple path read.
  - `install_config_storage_group_ashift` — takes a positional
    index argument that interpolates into the jq path.
  - `install_config_gpu` — array reader with the string default
    `"auto"`.
  - `_install_config_array` — private helper used by array-typed
    accessors.
- **Out of scope**: the install-state schema
  (`_INSTALL_STATE_SCHEMA` in `lib/install-state.sh`) is not
  linked to the new install-config schema, even though
  `install_state_write` consumes many install-config accessors.
  Cross-schema wiring is its own deepening.

## Testing Decisions

- **What makes a good test**: drive each accessor via its public
  name (`install_config_kernel` etc.) with a fixture
  `install.jsonc`, assert the emitted output. Do not poke at
  `_INSTALL_CONFIG_SCHEMA` directly or assert the existence of
  generated functions — those are implementation. The output is
  the contract.
- **Modules to test**: `lib/install-config.sh`. Tests live in
  `tests/install-config.bats`.
- **Test shape**:
  - One parameterised bats loop iterates the schema. For each
    entry it asserts (a) the schema default is emitted when the
    jq path is absent, (b) the configured value is emitted when
    the jq path is present.
  - Dedicated cases for each of the four specials —
    `packages_groups`, `storage_group_ashift`, `gpu`, plus
    array-with-no-default behaviour
    (`desktop`, `packages_extra`).
  - Dedicated cases for the bool null-distinction: literal
    `null` falls back to the default; explicit `false` does not.
- **Prior art**: `tests/install-state.bats` already tests the
  install-state wire format using its schema table. Shape and
  fixture pattern transfer directly.
- **Coverage parity**: every assertion currently in
  `tests/install-config.bats` is preserved in the new structure
  (parameterised loop covers the regular 21, special cases
  cover the four).

## Out of Scope

- Linking `install_state_write`'s `--arg` / `--argjson` jq
  invocation to the new schema. Cross-file refactor; separate
  deepening.
- Renaming any existing `install_config_*` accessor. Call sites
  stay byte-identical.
- Changing the Install Config JSON shape, validation rules, or
  any default value. This is a pure refactor.
- Touching `cfgo` / `jsonc_read` / `jsonc_strip` internals.

## Further Notes

- **Single commit** — the schema, generator loop, dispatcher,
  specials, and test rewrite land together. The generated
  wrappers must exist before the old hand-written ones are
  deleted, but both forms cannot coexist (same function names).
- **Eval is deliberate** — alternatives (rip wrappers / static
  one-liners / code-gen script writing the wrappers to disk)
  were considered and rejected in ADR 0015.
- **Pattern mirror**: same shape as `_INSTALL_STATE_SCHEMA` in
  `lib/install-state.sh`. Future readers familiar with one will
  recognise the other.
