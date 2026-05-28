# Categorized List Parser + first consumer (host packages.repo); ADR 0022

Status: ready-for-agent

## Parent

`.scratch/package-list-categorization/PRD.md`

## What to build

The tracer-bullet slice that introduces the schema change. Adds the
deep Categorized List Parser module, wires it into the pacstrap list
builder for `packages.repo`, migrates the existing host configs to
the new 2-level shape, and lands the schema ADR plus glossary update.

### Parser

A new pure Bash function (or small library) that takes:

- A JSON value (as produced by `jq` over JSONC).
- A leaf-type tag: `"string"` (package lists) or `"bool"` (toggle
  maps — added by issue 05/06; the function must accept the
  parameter from day one).

Validation rules:

- Top-level value must be an object.
- Keys must match `^[a-z0-9-]+$`.
- Values must be arrays (when `leaf_type=string`) or objects (when
  `leaf_type=bool`).
- Leaves must be the declared type (string or bool).
- Depth is exactly two — no further nesting.
- Empty categories are permitted and contribute nothing.

Output:

- `string` mode → sorted, deduped array of leaf strings.
- `bool` mode → sorted, deduped array of keys whose value is `true`.

Failure: abort via the repo's standard `error` helper with a precise
message naming the offending JSON path. No partial parse.

### First consumer

`lib/packages.sh` (the pacstrap list builder) and any other read site
that currently does `jq -r '.packages.repo[]?'` over the merged host
JSON switch to call the parser with `leaf_type=string`.

### Host config migration

- `hosts/core/config.jsonc:packages.repo` reshaped from
  `["parallel", "extra-cmake-modules"]` to a 2-level object. Category
  names operator's choice; suggestion:
  ```jsonc
  "repo": { "misc": ["parallel", "extra-cmake-modules"] }
  ```
- `hosts/desktop/config.jsonc:packages.repo` reshaped from its
  current flat array to a 2-level object. Category names operator's
  choice; suggested split mirrors logical groupings (browsers, dev,
  media, gaming, system, etc.).
- `packages.aur` in both files stays flat at this stage — issue 06
  migrates it.

### Tests

Table-driven unit tests for the parser. Inputs: JSON + leaf-type
tag. Outputs: expected flat list, OR expected non-zero exit with
error message naming offending path. Coverage:

- Valid 2-level object → correct flat output.
- Valid object with empty category → no error, no contribution.
- Duplicates across categories → output deduped.
- Bool-mode mixed true/false → only `true` keys emitted.
- Top-level array → error.
- Depth 1 (string leaf at top) → error.
- Depth 3 → error naming offending path.
- Invalid category name (`Browsers`, `media_apps`, `bad!`) → error
  naming rejected key.
- Wrong leaf type (`"yes"` in bool mode; `true` in string mode) →
  error naming leaf path and expected type.
- Empty top-level object → empty output, no error.

Test harness follows the bats style already used in `.os/tests/`.

### ADR

`docs/adr/0022-categorized-list-schema.md` — captures the 2-level
rule, kebab-case categories, fail-fast validation, cosmetic-only
semantics, and the rationale for strict-only (no permissive
fallback).

### CONTEXT.md

Update the `Host Package List` glossary entry to describe the new
2-level categorized shape. Do NOT update `Desktop Environment
Adapter` or `Environment Runner` yet — those land with issue 06.

## Acceptance criteria

- [ ] A new parser module exists, pure (no I/O), with the validation
      rules above.
- [ ] `lib/packages.sh` uses the parser for `packages.repo`.
- [ ] `hosts/core/config.jsonc:packages.repo` is a 2-level object.
- [ ] `hosts/desktop/config.jsonc:packages.repo` is a 2-level object.
- [ ] `packages.aur` in both host configs is still a flat array.
- [ ] Parser unit tests cover all the listed cases and pass.
- [ ] A fresh install on `hosts/desktop` yields the same package set
      as before this change.
- [ ] Malformed configs (shape/leaf-type/category-name violations)
      fail at config-load time with a precise error.
- [ ] `docs/adr/0022-categorized-list-schema.md` exists.
- [ ] `CONTEXT.md:Host Package List` entry updated to reflect 2-level
      shape.

## Blocked by

None - can start immediately (can run in parallel with issues 1-3).
