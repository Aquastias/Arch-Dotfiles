# ADR 0013: `install/` sibling for install-side files

## Status
Accepted

## Context
ADR 0012 introduced the Program Config Tree at
`.os/programs/<cat>/<name>/configs/`, with a `manifest.jsonc` that
declares user-side file placement consumed by the Config Generator.

Two programs already shipped a `configs/` directory before ADR 0012:

- `programs/security/clamav/configs/` — `clamd.conf`,
  `freshclam.conf`, `user.conf` (copied to `/etc/clamav/` by
  `install.sh`)
- `programs/security/rkhunter/configs/` — `rkhunter.conf` (copied
  to `/etc/rkhunter.conf` by `install.sh`)

These files are **install-side scaffolding** — system paths the
install script writes during chroot. They are not user-side
dotfiles and have no manifest.

So `configs/` is overloaded: install-side (existing) vs Program
Config Tree (ADR 0012). The Config Generator can either:

- silently skip `configs/` dirs without a manifest (the slice-01
  tracer's choice), which also silently skips a real migration
  that forgets the manifest, or
- treat missing manifest as an error, which breaks every install
  that ships clamav or rkhunter today.

Neither option is acceptable as a permanent state.

## Decision
Rename the install-side directory in every affected program from
`configs/` to `install/`. After the rename:

- `configs/` is unambiguously the Program Config Tree per ADR 0012.
- `install/` is the install script's private input directory —
  anything in there is read by the program's `install.sh`.
- The Config Generator requires a `manifest.jsonc` in every
  `configs/` it walks. Missing manifest is a loud error.

Affected programs: `clamav`, `rkhunter`. Their `install.sh`
references must be updated alongside the rename, atomically per
program.

## Considered alternatives

**Keep `configs/` overloaded; gate generator on `manifest.jsonc`
presence.** Permanent silent-skip ambiguity: a forgotten manifest
in a real migration is indistinguishable from an install-side
program. Slice-01's tracer used this gate as scaffolding; it is
not a long-term contract.

**Rename to `etc/`.** Mirrors where the files land on disk
(`/etc/clamav/`). Misleading if a future program writes to
`/usr/`, `/var/`, or `/run/`.

**Rename to `system/`.** Symmetric with System Program vs User
Program. Generic, but says nothing about who consumes the files.

`install/` names the consumer (the install script). Anything in
`install/` is read by `install.sh`; anything in `configs/` is
read by the Config Generator. The names describe the contract,
not the destination, which is the property that survives future
churn (e.g. impermanence may redirect destinations later without
changing what `install.sh` actually reads).

## Consequences

- The rename is a one-time per-program edit: move the directory,
  edit the `cp`/`install` paths in `install.sh`. Per-program and
  atomic, matching the ADR 0012 migration model.
- The Config Generator can drop its `manifest.jsonc`-presence gate
  on `configs/`. A missing manifest becomes a validation error,
  surfaced loudly at install time (and earlier via
  `--validate-only` in CI).
- No glossary entry needed. `install/` is a private convention
  between each program and its `install.sh`; the Config Generator
  never reads it. This stays out of `CONTEXT.md`.
- The slice-01 bats test "configs/ without manifest.jsonc is
  skipped (pre-migration)" is obsolete after the rename and
  should be removed.
- A future audit check could assert "every `configs/` has a
  `manifest.jsonc`" to catch missed renames. Not required for
  this ADR; the generator itself enforces it at run time.

## Related deferred decisions
The grill session that produced this ADR also resolved six smaller
implementation choices that do not warrant their own ADRs but
should be recorded for the future implementer:

1. **Fixture relocation.** Move `programs/_fixture/hello/` to
   `.os/tests/fixtures/programs/hello/`. CLI takes a
   `PROGRAMS_ROOT` override (already supported). Production tree
   ships no fixture.
2. **CLI variant wiring.** The Config Generator CLI calls
   `load_user_config <user> | jq '.variants // {}'` and passes
   the result to `cg_resolve_variants`. Today's `'{}'` is a
   slice-02 scaffold and out of contract with the CONTEXT.md
   entry for Config Generator.
3. **Test co-location.** Cross-module integration tests stay in
   the primary module's bats file (`configs-variant-resolver.bats`
   for the resolver/`load_user_config` integration, etc.). No
   dedicated integration bats file.
4. **No `--continue-on-error` flag.** Fail-fast aligns with the
   PRD's "loudly and early". CI gating happens via
   `--validate-only` before merge, not at install time.
5. **`print_status` in the CLI.** The Config Generator CLI sources
   `lib/shell-stdlib.sh` and routes stderr through
   `print_status error`. Stdout (the `--dry-run` plan, the
   `--validate-only` silence) stays plain so diffs work.
6. **`--dry-run --validate-only` rejection.** Combining the two
   flags is a usage error (`exit 2`). The flags answer
   conceptually distinct questions; silent-precedence would hide
   CI bugs.
