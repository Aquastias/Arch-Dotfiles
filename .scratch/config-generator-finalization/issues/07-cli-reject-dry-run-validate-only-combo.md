Status: done

# CLI: reject --dry-run --validate-only combination

## Parent

`.scratch/config-generator-finalization/PRD.md`

## What to build

The CLI today accepts `--dry-run --validate-only` together and
silently behaves as `--validate-only`. A CI script that
mistakenly sets both flags would never notice that no plan was
printed.

This slice rejects the combination as a usage error. The flags
answer conceptually distinct questions; combining them is
ambiguous and silent-precedence hides bugs.

Behavior:

- If both flags are present, the CLI calls `usage()` and exits
  2 (matching other usage errors).
- `--help` documents the mutual exclusion.

Add one bats case in `configs-cli-flags.bats` asserting `exit 2`
when both flags are passed.

## Acceptance criteria

- [x] CLI exits 2 when both `--dry-run` and `--validate-only`
      are passed
- [x] CLI's usage / help output names the mutual exclusion
- [x] A bats case in `configs-cli-flags.bats` verifies the
      exit code
- [ ] All other CLI flag bats cases still pass
- [ ] `tests/run.sh` still passes
- [ ] `tests/audit.sh` still passes

## Blocked by

None — can start immediately.

## Comments

- 2026-09-27 audit: 12223f5 (configs-cli-flags.bats). Later: ADR 0134 (c8442fe)
  deleted the config generator. Remaining unticked lines are suite/VM runs not
  re-verifiable now.
