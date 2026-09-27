Status: done

# Resolver: loud error on missing manifest in configs/

## Parent

`.scratch/config-generator-finalization/PRD.md`

## What to build

Drop the slice-01 manifest-presence gate from
`cg_resolve_variants`. After ADR 0013 and slices 01/02 of this
PRD, `configs/` is unambiguously the Program Config Tree.

The resolver currently silently skips a `configs/` directory
without `manifest.jsonc`. This slice flips that contract: a
`configs/` lacking a manifest is a validation error, surfaced
to stderr, with non-zero exit. Same treatment for
`configs@<variant>/` directories lacking a manifest.

The bats case "configs/ without manifest.jsonc is skipped
(pre-migration)" in `configs-variant-resolver.bats` documented
the old scaffold contract and is obsolete. Replace it with a
positive assertion that a `configs/` without a manifest errors.

## Acceptance criteria

- [x] `cg_resolve_variants` errors when a `configs/` exists
      without a `manifest.jsonc`
- [x] The error message names the affected program (cat/name)
      and the missing file
- [x] `configs-variant-resolver.bats` loses the "skipped"
      case and gains a positive "errors" case
- [ ] All other resolver bats cases still pass
- [ ] `tests/run.sh` still passes
- [ ] `tests/audit.sh` still passes

## Blocked by

- `01-rename-clamav-configs-to-install.md`
- `02-rename-rkhunter-configs-to-install.md`

## Comments

- 2026-09-27 audit: f7f25dc (configs-variant-resolver.bats). Later: ADR 0134
  (c8442fe) deleted the config generator. Remaining unticked lines are suite/VM
  runs not re-verifiable now.
