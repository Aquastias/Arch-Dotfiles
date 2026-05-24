Status: done

# CLI: stderr via print_status; ensure Shell Stdlib is staged for chroot

## Parent

`.scratch/config-generator-finalization/PRD.md`

## What to build

The Config Generator CLI writes errors as plain `echo ... >&2`.
Issue 06 of `.scratch/per-program-config-tree/` required
`print_status` family integration so generator output matches
the rest of the install transcript.

This slice:

- Sources `lib/shell-stdlib.sh` once in the CLI.
- Routes existing stderr writes through `print_status error`
  (and `print_status warning` where warnings exist).
- Leaves stdout writes (the `--dry-run` plan, the
  `--validate-only` happy-path silence) as plain bytes so two
  consecutive runs diff cleanly.

Cross-cutting check: the Runner invokes the CLI inside
`arch-chroot`. The chroot staging in `lib/chroot.sh` must
expose `lib/shell-stdlib.sh` and `lib/shell/` to anything
running in the chroot. If those files are not currently staged,
this slice adds the staging.

If `tests/audit.sh` already covers the chroot staging manifest
(it does — check #2 "Staged file manifest"), extend the audit
to include the Shell Stdlib files added here.

## Acceptance criteria

- [ ] CLI sources `lib/shell-stdlib.sh` at startup
- [ ] All stderr writes in the CLI use `print_status` (error or
      warning as appropriate)
- [ ] Stdout writes are unchanged — `--dry-run` plan stays raw
      bytes; `--validate-only` happy path stays silent
- [ ] `lib/shell-stdlib.sh` and `lib/shell/` are staged into the
      chroot environment (verify by reading `lib/chroot.sh` or
      by adding the staging if absent)
- [ ] `tests/audit.sh` covers any staging additions and passes
- [ ] `tests/run.sh` still passes — the existing CLI bats keep
      working (stderr matchers may need updating for prefix
      changes)

## Blocked by

None — can start immediately.
