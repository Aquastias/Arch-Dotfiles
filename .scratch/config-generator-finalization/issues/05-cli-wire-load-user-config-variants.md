Status: ready-for-agent

# CLI: wire load_user_config → .variants into the resolver call

## Parent

`.scratch/config-generator-finalization/PRD.md`

## What to build

The Config Generator CLI calls `cg_resolve_variants` with a
literal empty variants map. This contradicts CONTEXT.md's entry
for Config Generator, which promises that it "reads the merged
User Core + User Config for a target user, resolves each
program's Config Variant".

This slice wires `load_user_config` (from `lib/configs.sh`) into
the CLI:

- When `--user <u>` is given, the CLI invokes
  `load_user_config <u>` and extracts the `.variants` object
  (or `{}` if absent).
- The resulting object is passed to `cg_resolve_variants`.
- When `--validate-only` is given without `--user`, the CLI
  skips variant resolution entirely (existing behavior — no
  change).

`load_user_config` already performs the User Core + User Config
deep merge. This slice does not introduce a parallel merger.

Add one bats case in `configs-cli-flags.bats` covering the end-
to-end integration: a temp `OS_DIR` with `users/core/config.jsonc`
declaring a House Default variant, `users/<u>/config.jsonc`
overriding one program's variant per-key, and the CLI producing
the right resolved tree.

## Acceptance criteria

- [ ] CLI with `--user <u>` invokes `load_user_config <u>`
      and passes `.variants` to the resolver
- [ ] CLI with `--validate-only` and no `--user` skips
      variant resolution (no behavior change)
- [ ] A bats case in `configs-cli-flags.bats` verifies House
      Defaults applied from User Core
- [ ] The same bats case verifies User Config overrides per-
      key (the standard deep-merge contract from `configs.sh`)
- [ ] `tests/run.sh` still passes
- [ ] `tests/audit.sh` still passes

## Blocked by

None — can start immediately.
