Status: ready-for-agent

# Drive Install Config accessors from a schema table

## Parent

`.scratch/install-config-schema-table/PRD.md` (ADR 0015)

## What to build

Replace the 25 hand-written `install_config_*` accessors in the
Install Config reader module with a schema-driven implementation:
a single pipe-delimited array `_INSTALL_CONFIG_SCHEMA` at the top
of the module, a single `install_config_get <name>` dispatcher, and
the 21 regular named wrappers generated from the schema via a
source-time eval loop. Four genuinely-special accessors remain
hand-written below the schema. Tests collapse to a parameterised
loop over the schema plus dedicated cases for the four specials
and the bool null-distinction.

Schema entry format (from PRD §Implementation Decisions):

```
name|jq_path|type|default
```

- `type` ∈ `scalar`, `bool`, `array`
- empty default field = emit empty string when path absent
  (preserves today's behaviour for `hostname`, `age_key_url`,
  `dotfiles_repo`)

Dispatcher rules:

- `scalar` reads via `cfgo` (jq `// empty`)
- `bool` reads via `jsonc_read` and distinguishes literal `null`
  (treated as absent → default) from literal `false` (treated as
  value)
- `array` reads via the existing `_install_config_array` helper

Generation:

```
for spec in "${_INSTALL_CONFIG_SCHEMA[@]}"; do
  IFS='|' read -r name _ _ _ <<< "$spec"
  eval "install_config_${name}() { install_config_get ${name}; }"
done
```

A short header comment above the eval loop points future readers
at the schema as the canonical declaration site.

Four hand-written specials remain (behaviour unchanged):

- `install_config_packages_groups` — custom jq filter
- `install_config_storage_group_ashift` — takes a positional
  index argument
- `install_config_gpu` — array with the string default `"auto"`
- `_install_config_array` — private array-reader helper

Single commit. The generated wrappers and the existing
hand-written ones share names and cannot coexist — additive
split is impossible. `CONTEXT.md` is unaffected (no domain change).

## Acceptance criteria

- [ ] `_INSTALL_CONFIG_SCHEMA` array exists at the top of the
      Install Config reader module with one row per regular
      accessor (21 rows total), each in
      `name|jq_path|type|default` format.
- [ ] `install_config_get <name>` exists as a statically-defined
      function that looks up the schema row by name and
      dispatches on type.
- [ ] All 21 generated wrappers exist via the eval loop and
      forward their call to `install_config_get`.
- [ ] The four specials (`install_config_packages_groups`,
      `install_config_storage_group_ashift`,
      `install_config_gpu`, plus `_install_config_array` helper)
      remain hand-written below the schema.
- [ ] Every accessor produces byte-identical output to today's
      hand-written version for the same input, including the
      bool null-distinction (`null` and absent → default;
      explicit `false` → `false`).
- [ ] An empty default field in the schema results in an empty
      string when the jq path is absent (matching today's
      behaviour for `hostname`, `age_key_url`, `dotfiles_repo`).
- [ ] No old hand-written wrapper survives for any name covered
      by the schema.
- [ ] A short header comment above the eval loop points future
      readers at the schema.
- [ ] `tests/install-config.bats` is restructured: one
      parameterised loop over the schema asserts
      default-on-absent + value-on-present per entry; dedicated
      cases cover the four specials and the bool
      null-distinction.
- [ ] Coverage parity: every assertion present in today's
      `tests/install-config.bats` is preserved in the new
      structure.
- [ ] `shellcheck` passes on every changed file.
- [ ] Full `bats` suite passes (regressions in any consumer of
      `install_config_*` accessors must surface here).
- [ ] No call site of any `install_config_*` accessor changes.
- [ ] Single commit, conventional-commit style, capitalized
      after the prefix.

## Blocked by

None - can start immediately.
