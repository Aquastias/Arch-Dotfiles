Status: done

# PRD: Install Config Reader and Install State Modules

## Problem Statement

The Install Config (`.os/install.jsonc`) is a named domain entity in
`CONTEXT.md`, but no module owns its schema. Every consumer reaches into
`CONFIG_FILE` directly via `cfg`/`cfgo` plus a hand-rolled default
fallback (`X="${X:-default}"`). The same default values are duplicated
across the codebase:

- `options.impermanence.dataset` default `"rpool/persist"` appears in
  `lib/chroot.sh`, `lib/validation.sh`, and `lib/chroot/load-state.sh`
  (with a comment explicitly calling out the duplication).
- `options.kernel` (`lts`), `options.bootloader` (`systemd-boot`),
  `options.swap` (`true`), `options.esp_size` (`512M`),
  `system.keymap` (`us`), `impermanence.mount` (`/persist`) each repeat
  the same pattern across multiple modules.

The host→chroot wire protocol — `install-state.json` — is also a shadow
protocol: written ad-hoc in `lib/chroot.sh::configure_system` via a
multi-line `jq -n --arg ...` block, read field-by-field in
`lib/chroot/load-state.sh`, and mutated by a third file (`lib/secrets.sh`)
to splice in tmpfs paths. Schema drift between writer and reader is a
runtime-only failure mode; defensive defaults are encoded on both sides
and must be kept in sync by hand.

The lack of a schema seam means:

- Adding a new Install Config option is an N-site change.
- Defaults are silently authoritative in whichever module reads them
  first.
- Tests that exercise default behavior require constructing
  `install.jsonc` fixtures rather than calling typed accessors.

## Solution

Introduce two new modules that own the schema and the wire format
respectively:

**`lib/install-config.sh` — Install Config Reader.** Typed accessor
functions named `install_config_*` (one per config field), each
returning the value from `CONFIG_FILE` with the canonical default
applied. Built on top of existing `cfg`/`cfgo` primitives. Schema
defaults live here and nowhere else.

**`lib/install-state.sh` — Install State protocol.** Owns the
host↔chroot wire format. Exposes `install_state_write <path>` on the
host (consumes `install_config_*` accessors and other resolved state to
populate the JSON document) and `install_state_load <path>` on the
chroot (replaces `lib/chroot/load-state.sh`). The field list is
declared once; defensive JSON-level defaults in the chroot reader
become dead code and are removed.

Existing consumers (`lib/chroot.sh`, `lib/packages.sh`,
`lib/environment.sh`, `lib/validation.sh`, etc.) are migrated to call
the new accessors instead of duplicating defaults inline.

## User Stories

1. As an installer maintainer, I want to add a new Install Config
   option in one place, so that I don't have to grep for default-fallback
   patterns across the codebase.
2. As an installer maintainer, I want a single source of truth for every
   Install Config default value, so that changing a default cannot
   silently disagree between modules.
3. As an installer maintainer, I want typed accessors named after the
   fields they read, so that grep tells me every consumer of a given
   option without false positives.
4. As a contributor reading `lib/chroot.sh`, I want default values to
   be hidden behind a named accessor, so that the orchestration logic
   reads as orchestration rather than schema-plus-orchestration.
5. As an installer maintainer, I want the host→chroot wire format
   declared once, so that schema drift between writer and reader becomes
   a code-review-class problem rather than a runtime-only failure mode.
6. As a contributor inside the Chroot Configuration Module, I want a
   single `install_state_load` call to populate every state variable, so
   that I don't have to maintain per-field `jq -r '.X // "default"'`
   lines.
7. As a test author, I want to call typed Install Config accessors
   directly in bats tests, so that I don't have to construct
   `install.jsonc` fixtures to assert default behavior.
8. As a test author, I want to round-trip `install_state_write` and
   `install_state_load` in a test, so that schema drift is caught by
   the test suite rather than by a failed install.
9. As an installer maintainer working on the Secrets Module, I want
   secrets paths added to Install State through the same interface as
   other fields, so that the schema is fully owned by one module
   instead of mutated by three.
10. As an installer maintainer, I want existing call sites migrated
    incrementally, so that I can land the refactor without a single
    big-bang change.

## Implementation Decisions

- **Two separate modules**, not one. Install Config is host-only and
  owns operator-authored schema with defaults. Install State is the
  derived host→chroot transport with a chroot-side reader. Combining
  them would force the chroot to source code (jsonc parsing, mode
  detection, environment resolution) it does not need.
- **Accessor naming uses `install_config_*` long-form**, matching the
  dominant `lib/` convention (`iso_resolver_*`, `seed_generator_*`,
  `sentinel_watcher_*`, `secrets_*`). Verbose at the call site,
  grep-friendly, self-documenting.
- **Existing `cfg` / `cfgo` primitives are kept**; `install_config_*`
  wraps them. No callers of `cfg`/`cfgo` outside the Install Config
  Reader after migration (except those reading non-schema fields like
  diagnostics).
- **Defaults live in `install-config.sh` only.** Chroot-side
  defensive JSON defaults (`.impermanence.dataset // "rpool/persist"`
  etc.) in today's `load-state.sh` are removed. Install State writer
  is the schema authority: if a field is missing in the wire format,
  that is a bug in the writer.
- **Install State field list declared once** as a shared array or
  similar shell construct; the writer and reader iterate it instead of
  hard-coding field names twice.
- **`lib/chroot/load-state.sh` is deleted**; the chroot-side reader
  becomes `install_state_load` invoked from `configure.sh` and other
  chroot sub-scripts.
- **`lib/secrets.sh::_secrets_write_state` is refactored** to use the
  Install State module's field-update interface instead of a hand-rolled
  `jq` mutation.
- **Migration order**: ship `install-config.sh` first with accessors
  for every existing default site; migrate consumers one module at a
  time (`lib/chroot.sh`, `lib/packages.sh`, `lib/environment.sh`,
  `lib/validation.sh`); then ship `install-state.sh` and replace
  `load-state.sh`; finally remove the now-dead chroot-side defaults.

## Testing Decisions

Good tests here exercise the external behavior of each accessor and
the round-trip semantics of the wire format. Schema knowledge is the
asset; tests should fail loudly when it drifts.

- **`install-config.sh` tests** — one bats file per accessor group
  (options, system, impermanence, environment). For each: a test with
  the field present (returns the value) and a test with the field
  absent (returns the documented default). Prior art:
  `tests/configs.bats`, `tests/environment-validation.bats`.
- **`install-state.sh` tests** — round-trip: build a fake state via
  the writer, load it via the reader, assert every field comes back
  intact. A second test asserts that a missing field in the wire
  format is treated as an error (no defensive defaults). Prior art:
  `tests/chroot-load-state.bats` is the closest existing pattern.
- **Migration regression** — the existing chroot-load-state bats file
  is updated (or replaced) to point at `install_state_load`. No
  behavior change is expected; any new failure indicates a missed
  field.
- **Consumer migration tests** stay as-is. `lib/chroot.sh`,
  `lib/packages.sh`, etc. already have tests
  (`tests/chroot-configure.bats`, `tests/packages.bats`) and should
  continue passing without modification — the refactor must be
  behavior-preserving.

Tests do not assert internal implementation details (which file
contains `cfgo`, whether accessors are functions vs. variables). They
assert that the accessor returns the right value for the right input.

## Out of Scope

- Changing any Install Config schema (no new fields, no renamed
  fields, no removed fields).
- Validating Install Config beyond what `lib/validation.sh` already
  does today. Validation may eventually be a third module, but that is
  a separate decision.
- Changing the JSONC parsing primitives in `lib/jsonc.sh`.
- Restructuring `lib/config.sh` (template generation, mode detection,
  summary printing). It stays as-is for now; its accessors that
  currently inline defaults will migrate to `install_config_*` calls.
- Adding new Install State fields. The migration moves what's there
  today; new fields are a separate PRD.
- The persist-verbs extraction (separate PRD:
  `persist-verbs-extraction`).
- The curated-defaults fold-in (separate PRD:
  `curated-defaults-fold-in`).

## Further Notes

This refactor enables but does not require future work:

- A Validation Module split (`lib/validation.sh` could shrink once
  schema knowledge moves out).
- Generating an `install.jsonc` template from the accessor list rather
  than maintaining a hand-written template in `lib/config.sh`.
- Typed accessor reuse in the runtime tools under `.os/tools/` (e.g.
  the Impermanence Tool already re-derives defaults like
  `IMPERMANENCE_MOUNT:=/persist`; it could source `install-config.sh`
  for parity).

Naming convention rationale documented in CONTEXT.md and the prior
`/grill-with-docs` session; no separate ADR (the choice matches
existing conventions and is not surprising).
