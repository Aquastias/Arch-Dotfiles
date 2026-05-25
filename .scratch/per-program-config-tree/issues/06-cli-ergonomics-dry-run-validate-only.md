Status: done

# CLI ergonomics: --dry-run and --validate-only

## Parent

`.scratch/per-program-config-tree/PRD.md`

## What to build

Add the two operator-facing flags to the Config Generator CLI.

- `--dry-run` — runs the full pipeline through Plan Builder and
  Conflict Detector but performs no writes. Prints the plan in a
  human-readable form (one line per planned entry, showing src and
  dst at minimum) plus any conflict messages. Exit code matches
  what a real run would exit with (zero on clean, non-zero on
  conflict or validation error).
- `--validate-only` — runs Manifest Validator and Variant Resolver
  only; no plan output, no writes. Exits zero when every relevant
  manifest validates and every relevant variant resolves; non-zero
  otherwise. Intended for cheap CI / pre-commit gating.

Both flags coexist with `--user`. `--validate-only` without
`--user` validates manifests globally without per-user variant
resolution; with `--user` it also resolves that user's variants.

Plan output for `--dry-run` is stable across runs (already
guaranteed by slice 05's deterministic plan ordering) so it
diff-friendly.

Both flags integrate with the existing `print_status` family for
operator-visible output.

## Acceptance criteria

- [ ] `--dry-run --user <u>` prints the plan, performs no writes
      to `~/.dotfiles/.stow/<u>/`, exits zero on clean
- [ ] `--dry-run --user <u>` exits non-zero when the plan would
      conflict with the legacy stow tree; conflict messages
      printed
- [ ] `--dry-run --user <u>` exits non-zero when a manifest fails
      validation; validation errors printed
- [ ] `--validate-only --user <u>` validates manifests AND resolves
      variants for that user; exits 0/1; no plan output, no writes
- [ ] `--validate-only` without `--user` validates manifests
      globally (no per-user variant resolution); exits 0/1
- [ ] Plan output is stable byte-for-byte across two runs with
      identical inputs (regression-protects deterministic ordering
      from slice 05)
- [ ] A test (bats or shell) covers each flag's exit-code matrix
      and the no-writes guarantee for `--dry-run` and
      `--validate-only`
- [ ] `tests/audit.sh` still passes

## Blocked by

- `01-tracer-end-to-end-pipeline.md`
