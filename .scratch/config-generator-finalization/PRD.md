Status: ready-for-agent

# PRD: Config Generator finalization (ADR 0013 rollout)

References: ADR 0013, ADR 0012, `.scratch/per-program-config-tree/`.

## Problem Statement

The Config Generator shipped across slices 01, 02, and 06 with
seven open implementation decisions, captured in ADR 0013 (one
primary decision and six "related deferred" items). Until those
decisions land in code, the tool is out of contract with its own
glossary entry and ships scaffolding that future readers will
trip over.

Specifically:

- The directory name `configs/` is overloaded today. Two existing
  programs (`clamav`, `rkhunter`) ship `configs/` directories
  holding install-side scaffolding (`/etc/...` config files
  consumed by `install.sh`), not Program Config Trees. The
  Config Generator's slice-01 tracer gates on `manifest.jsonc`
  presence to silently skip these — which also silently skips a
  real migration that forgets the manifest. The contract for
  what `configs/` means is ambiguous in code.
- A fixture program (`programs/_fixture/hello/`) ships in the
  production tree solely because the slice-01 acceptance criterion
  exercises the real CLI walking the real `programs/` root. Every
  installed host has a `~/.config/hello/greeting` file forever.
- The Config Generator CLI calls `cg_resolve_variants` with an
  empty variants map — User Core's `variants` (House Defaults)
  and User Config's per-key overrides are ignored. This
  contradicts the CONTEXT.md entry for Config Generator, which
  promises that it "reads the merged User Core + User Config for
  a target user, resolves each program's Config Variant".
- The CLI writes errors as plain text to stderr, where issue 06's
  acceptance criterion required `print_status` family integration
  for operator-visible output.
- The CLI accepts `--dry-run --validate-only` together, silently
  running as `--validate-only`. A CI script that mistakenly sets
  both flags would never notice that no plan was printed.

## Solution

A single feature-scoped slice that lands the seven ADR 0013
decisions and leaves the Config Generator fully in contract.

### Headline change

Rename install-side `configs/` directories to `install/` across
the repo. After the rename, `configs/` is unambiguously the
Program Config Tree; a missing `manifest.jsonc` is a loud
validation error rather than a silent skip. The two affected
programs (`clamav`, `rkhunter`) get atomic per-program edits:
move the directory, update `install.sh` paths.

### Supporting changes

- Drop the slice-01 manifest-presence gate from `cg_resolve_variants`.
  Bats coverage for "configs/ without manifest is skipped" is
  obsolete and removed; replaced by a positive assertion that the
  resolver errors on a `configs/` lacking a manifest.
- Relocate `programs/_fixture/hello/` to
  `.os/tests/fixtures/programs/hello/`. Bats files use the
  fixture path via the existing `PROGRAMS_ROOT` override. Drop
  the production `_fixture/` tree.
- Wire `load_user_config <user>` into the Config Generator CLI.
  When `--user` is given, the CLI reads the merged User Core +
  User Config, extracts `.variants`, and passes it to
  `cg_resolve_variants`. House Defaults from User Core become
  the per-host norm, overridden per-key by each User Config.
- Source `lib/shell-stdlib.sh` from the CLI and route stderr
  through `print_status error` / `print_status warning`. Stdout
  (the `--dry-run` plan, the `--validate-only` silence) stays
  plain bytes so two runs against identical inputs still
  diff-clean.
- Reject `--dry-run --validate-only` together as a usage error
  (`exit 2`). The flags answer conceptually distinct questions;
  silent precedence hides CI bugs.

## User Stories

1. As the operator, I want one canonical meaning for
   `configs/` in `.os/programs/<cat>/<name>/`, so that I never
   have to ask "is this a Program Config Tree or install-side
   scaffolding?"
2. As the operator, I want a missing `manifest.jsonc` inside a
   `configs/` directory to fail loudly, so that a forgotten
   manifest during a real program migration cannot be mistaken
   for an unmigrated program.
3. As the operator migrating `clamav`, I want its install-side
   files to live in a directory that does not collide with the
   Program Config Tree, so that I can later add a `configs/`
   with a real manifest without ambiguity.
4. As the operator migrating `rkhunter`, I want the same
   atomic-per-program rename so that the convention is uniform
   across the repo from day one.
5. As a future contributor reading
   `programs/<cat>/<name>/install/`, I want the directory name
   itself to tell me who consumes the files, so that I do not
   need to grep `install.sh` to find out.
6. As the operator inspecting an installed host, I do not want
   `~/.config/hello/greeting` files lingering forever from a
   testing fixture, so that a clean install leaves a clean
   `$HOME`.
7. As a developer running bats locally, I want test fixtures to
   live under `.os/tests/fixtures/`, so that test data is
   colocated with the tests that consume it.
8. As the operator on a host with multiple users, I want User
   Core's `variants` to apply as House Defaults to every user
   on the host, so that I configure the typical setup once.
9. As an individual user on a shared host, I want my User
   Config's `variants.<program>` to override the House Default
   for that specific program, so that I can have minimal zsh
   when the house default is gaudy.
10. As the operator running `generate-configs.sh --user alex`,
    I want the CLI to actually consume `alex`'s merged variants
    map, so that what runs on disk matches what CONTEXT.md
    promises about the Config Generator.
11. As the operator watching install output, I want errors and
    warnings from the Config Generator to look like every other
    install step's output, so that the install transcript reads
    consistently end-to-end.
12. As an operator using `--dry-run` in a CI pipeline, I want
    plan output on stdout to remain plain bytes, so that two
    consecutive runs produce identical output and I can diff
    plans across PRs.
13. As an operator using `--validate-only` in a CI pre-merge
    gate, I want zero stdout output on success, so that the
    gate's log stays quiet on the happy path.
14. As a CI script author, I want the CLI to fail loudly if I
    pass `--dry-run --validate-only` together, so that I never
    ship a config that intended to print a plan but silently
    validated only.
15. As an agent landing future per-program migrations, I want
    the manifest-presence contract to be enforced by the
    resolver, so that I get immediate feedback if I forget the
    manifest in a new migration.
16. As an operator running `--validate-only` against a tree
    that has a half-migrated program (manifest typo), I want
    the validation error to surface that specific program with
    a clear message, so that I know exactly what to fix.

## Implementation Decisions

### Directory rename

Two programs are affected: `clamav` and `rkhunter`. For each:

- Move the existing `configs/` directory to `install/`.
- Update `install.sh` to point at `install/` rather than
  `configs/` (one or two `cp` / `install` paths each).

The rename is per-program and atomic: each program's directory
move and `install.sh` edit ship in one commit so the program is
either fully renamed or fully on the old layout. No flag day.

After both programs are renamed, the Config Generator drops the
slice-01 manifest-presence gate from `cg_resolve_variants`. A
`configs/` directory without a `manifest.jsonc` becomes a
validation error.

### Fixture relocation

`programs/_fixture/hello/` moves to `.os/tests/fixtures/programs/
hello/`. The Config Generator CLI already accepts a
`PROGRAMS_ROOT` env override (used by the slice-06 bats tests),
so the relocation is a directory move plus an update of any bats
files that hard-coded the production path. No production tree
ships a fixture program after this change.

### CLI variant wiring

The CLI grows a step between flag parsing and resolver invocation:

- When `--user <u>` is given, the CLI invokes `load_user_config
  <u>` (from `lib/configs.sh`) and extracts `.variants // {}`
  via `jq`.
- The resulting object is passed to `cg_resolve_variants`
  instead of today's literal `'{}'`.
- When `--validate-only` is given without `--user`, the CLI
  skips variant resolution entirely and walks all manifests
  globally (existing behavior — no change).

`load_user_config` already performs the User Core + User Config
deep merge, so this is a single shell-out, not a new merge
implementation.

### `print_status` integration

The CLI sources `lib/shell-stdlib.sh` once at startup. Error
messages currently emitted as plain `echo ... >&2` go through
`print_status error`. Warning-level messages (when added in
future slices) use `print_status warning`. Stdout output (the
plan in `--dry-run`, nothing in `--validate-only` happy path)
stays as raw bytes — no `print_status` wrapping, no ANSI codes,
so diffs work.

The chroot copy of Shell Stdlib must already be on PATH when
the Runner invokes the generator inside `arch-chroot`. Verify
this against `lib/chroot.sh`'s staging during implementation;
if Shell Stdlib is not staged for chroot, stage it.

### `--dry-run --validate-only` rejection

The CLI's flag-parsing block checks for the combination and
calls `usage()` (exit 2) when both are set. Documented in
`--help`.

### Drop slice-01 silent-skip test

The bats case "configs/ without manifest.jsonc is skipped
(pre-migration)" in `configs-variant-resolver.bats` documents
the slice-01 scaffold contract. After the rename it is wrong:
the resolver should error, not skip. Replace it with a positive
assertion that a `configs/` without a manifest is a validation
error.

## Testing Decisions

### What makes a good test

Test behavior at the module's public interface. For the rename,
the behaviors under test live at three layers:

- **Resolver layer.** `cg_resolve_variants` now errors when a
  `configs/` has no `manifest.jsonc`. One bats case in
  `configs-variant-resolver.bats` covers this.
- **CLI layer.** `generate-configs.sh` now uses real variants
  from `load_user_config`. One bats case in
  `configs-cli-flags.bats` sets up a temp `OS_DIR` with a
  populated `users/core/config.jsonc` + `users/<u>/config.jsonc`
  and asserts the CLI resolves a non-default variant.
- **CLI layer.** `generate-configs.sh` rejects
  `--dry-run --validate-only`. One bats case in
  `configs-cli-flags.bats` covers this with `[ "$status" -eq 2 ]`.

### Modules under test

- `configs-variant-resolver.bats` — gains the "missing manifest
  errors" case; loses the "missing manifest skipped" case.
- `configs-cli-flags.bats` — gains the "real variants via
  `load_user_config`" case and the "dry-run + validate-only
  rejected" case. Adjusts any case that hard-codes the production
  fixture path to the new test-fixtures path.

No new bats files. No tests for the `clamav` / `rkhunter` rename
itself — `tests/audit.sh` already validates that each system
program's `install.sh` exists; the rename leaves audit green
because it does not touch `config.jsonc`. The fact that `install.sh`
points at the new directory is exercised by VM tests when the
host actually installs `clamav` / `rkhunter`.

### Prior art

- `configs-variant-resolver.bats` (this PRD modifies it) —
  existing fixture-driven resolver tests.
- `configs-cli-flags.bats` (this PRD modifies it) — existing
  end-to-end CLI tests using `PROGRAMS_ROOT` + `HOME` overrides.
- `configs.bats` — `load_user_config` tests live here; this PRD
  reuses `load_user_config` from the CLI but does not add tests
  for it.

## Out of Scope

- Migration of any user-facing program (`kitty`, `zsh`,
  `claude`, etc.) into a Program Config Tree. This PRD ships
  the mechanism cleanup; per-program migrations are separate
  slices.
- Real Conflict Detector logic — slice 04 owns that.
- Plan Builder multi-program / system-program-per-user — slice
  05 owns that.
- Documentation of `install/` as a domain term in
  `CONTEXT.md`. It is a private convention per program, not a
  cross-module concept.
- A new audit check asserting "every `configs/` has a
  `manifest.jsonc`". Useful but not required for this PRD; the
  resolver enforces the contract at run time.
- A `print_status`-based dry-run plan format. The plan stays
  raw bytes on stdout so it diffs cleanly.
- Any change to `lib/profiles.sh` beyond what was already shipped
  in slice 01.

## Further Notes

This PRD is the implementation of ADR 0013, written after a
grill session in which the seven outstanding decisions were
walked one-by-one. The ADR is the design document; this PRD is
the work order. The two should not drift — if a decision here
contradicts ADR 0013, ADR 0013 wins.

After this PRD lands, the Config Generator is complete for slices
01, 02, and 06. The remaining open slices in
`.scratch/per-program-config-tree/issues/` are 03 (manifest
validator hardening), 04 (conflict detector), and 05 (plan
builder multi-program). Those are not blocked by this PRD and
can proceed in parallel.

If the chroot staging in `lib/chroot.sh` does not currently
stage `lib/shell-stdlib.sh` and `lib/shell/`, this PRD must add
that staging — without it, the CLI's `print_status` calls fail
when invoked from inside `arch-chroot` by the Runner. This is a
small but real cross-cutting concern flagged during ADR 0013's
grill.
