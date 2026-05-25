# ADR 0015: Install Config accessors generated from a schema table

## Status
Accepted

## Context
`lib/install-config.sh` exposed ~25 typed accessors
(`install_config_kernel`, `install_config_bootloader`,
`install_config_swap_enabled`, …), each a 2–3 line wrapper around
`cfgo` / `jsonc_read` with an inline default. Interface ≈
implementation; the Install Config schema (paths + defaults) was
implicit across 25 function bodies; defaults drifted; tests had to
be written per-accessor (60+ cases for the same shape). The same
repo already proved the alternative shape in `lib/install-state.sh`,
where `_INSTALL_STATE_SCHEMA` is the single source of truth for the
install-state wire format.

## Decision
Declare the Install Config schema as a single pipe-delimited array
at the top of `install-config.sh`:

```
_INSTALL_CONFIG_SCHEMA=(
  "kernel|.options.kernel|scalar|lts"
  "swap_enabled|.options.swap|bool|true"
  "desktop|.environment.desktop|array|"
  ...
)
```

Format: `name|jq_path|type|default`. Type ∈ `{scalar, bool, array}`.
Empty default field = emit empty string when path absent (matches
prior behaviour of `hostname`, `age_key_url`, `dotfiles_repo`).

A single `install_config_get <name>` dispatches on type and applies
the default. The 21 named wrappers
(`install_config_kernel`, `install_config_bootloader`, …) are
generated from the schema via a `for spec in …; do eval
"install_config_${name}() { install_config_get ${name}; }"; done`
loop at source time. Call-site names stay greppable
(via the schema), call sites unchanged.

Four accessors stay hand-written below the schema as
acknowledged specials:
- `install_config_packages_groups` — custom jq filter, not a path
- `install_config_storage_group_ashift` — takes a positional index
- `install_config_gpu` — array with a default (`auto`)
- `_install_config_array` — helper used by array-typed accessors

Tests collapse to a parameterised loop over the schema
(default-on-absent + value-on-present per entry) plus dedicated
tests for the four specials and the bool null-distinction.

## Considered alternatives
- **Rip the named wrappers, callers say `install_config_get kernel`
  directly.** Rejected: every call site changes, schema names leak
  into ~40+ call sites, loses argument-completion / shellcheck
  visibility of names.
- **Static hand-written one-liners below the schema** (no `eval`).
  Rejected: 21 lines of mechanical boilerplate; adding a field
  means touching two places; the whole point of the schema is to
  be the single declaration.
- **Code-gen script** that writes the wrappers to disk between
  marker comments. Rejected: CI ceremony to verify file matches
  schema; no runtime gain over `eval`.

## Consequences
- Schema is the single source of truth for Install Config defaults
  and jq paths. Adding a field = one schema row.
- `grep install_config_kernel` finds the schema row, not a function
  definition. Future readers must know the convention — hence this
  ADR. The schema lives at the top of the file with a comment
  pointing at the `eval` loop.
- Shellcheck does not see the generated function definitions.
  Acceptable: each wrapper is mechanically identical, and the
  shared body lives in `install_config_get`, which **is**
  shellcheck-visible.
- Cross-file follow-up exists: `install_state_write` in
  `install-state.sh` has 14 hand-written `--arg` / `--argjson`
  pairs that mirror the schema. Linking the two is out of scope;
  noted as a future deepening.
