Status: ready-for-agent

# PRD: Persist Materialization Verbs

## Problem Statement

"Materialize a Persist Mount" is the same domain operation in two
consumers:

- **Install-time** (`lib/chroot/impermanence.sh::impermanence_apply`)
  writes mount units + tmpfiles entries for Curated Persist Defaults
  and host-declared Persist Extensions, then moves live data onto the
  Persist Dataset.
- **Runtime tool** (`tools/impermanence.sh::cmd_add` / `cmd_remove`)
  performs the same materialization per-target, plus the inverse.

Today the shared primitives live in `lib/impermanence-common.sh`
(`imp_write_mount_unit`, `imp_link_wants`) but only cover the
lowest-level unit writes. Higher-level orchestration — tmpfiles entry
writes, data movement, systemd reload, host-config declaration — is
duplicated, with each consumer reinventing the sequencing.

The duplication has concrete consequences:

- Add-failure rollback exists in the runtime tool's `cmd_add` (cleans
  up unit + tmpfiles + host config on failure) but not in the
  install-time loop.
- The tmpfiles entry format (`d` vs `f`, mode bits) is rewritten in
  three places: install-time curated, install-time extensions, runtime
  add.
- A bug in any of these requires fixing the same logic in two files
  with no test coverage of the cross-consumer equivalence.

`CONTEXT.md` names the noun (**Persist Mount**) but no module owns the
verbs that materialize or tear it down.

## Solution

Grow `lib/impermanence-common.sh` with two orchestrating verbs and
three data-staging helpers. Both consumers compose them.

**Verbs (mount-only — no data movement):**

- `persist_apply <target> <kind>` — write the Persist Mount unit,
  write the tmpfiles entry, optionally reload+start systemd.
- `persist_unapply <target>` — stop the mount, remove the unit, remove
  the tmpfiles entry, daemon-reload.

**Data-staging helpers (separate, explicit):**

- `persist_stage_in_move <target>` — install-time: `mv` live data to
  the Persist Dataset. Used by the install-time loop because the
  rolled-back dataset will lose the live copy on next boot anyway.
- `persist_stage_in_copy <target>` — runtime add: `cp -a` live data to
  the Persist Dataset. Used by the runtime tool because the bind mount
  activates immediately and the original must remain until covered.
- `persist_restore_data <target>` — runtime `remove --yes`: move data
  from the Persist Dataset back to the live path.

`lib/chroot/impermanence.sh` and `tools/impermanence.sh` are refactored
to compose these verbs instead of duplicating the sequencing.

This split is recorded in ADR 0009 (verbs omit data movement). The
asymmetry between install-time `mv` and runtime `cp` is also documented
in `CONTEXT.md` (Persist Mount entry).

## User Stories

1. As an impermanence-feature maintainer, I want add-failure rollback
   to behave identically in install-time and runtime contexts, so that
   a partial materialization cannot leave the system in an
   inconsistent state.
2. As an impermanence-feature maintainer, I want one place to fix a
   bug in tmpfiles-entry generation, so that the runtime and install
   paths cannot drift.
3. As an impermanence-feature maintainer, I want to extend
   materialization (e.g. to add a new sentinel file alongside every
   mount), so that I change one verb instead of two procedural blocks.
4. As an operator running `os impermanence remove <path>`, I want the
   default to leave persisted data untouched, so that I cannot
   accidentally destroy state without an explicit opt-in.
5. As an operator running `os impermanence remove --yes <path>`, I
   want my data moved back to the live path, so that I can fully
   undo a previous `add`.
6. As a contributor reading the install-time loop, I want the choice
   of `mv` (move) to be visible at the call site, so that the
   asymmetry with runtime `cp` is documented in the call sequence
   rather than buried in a function's mode flag.
7. As a contributor reading the runtime `cmd_add`, I want the choice
   of `cp` (copy) to be visible at the call site for the same reason.
8. As a test author, I want to test `persist_apply` and
   `persist_unapply` against a temporary directory, so that mount-unit
   and tmpfiles-entry correctness is verified without filesystem
   side effects on the real `/persist`.
9. As a test author, I want to test data-staging helpers
   independently, so that filesystem operations are covered without
   mocking systemd.
10. As an installer maintainer adding a future verb (e.g. "promote
    a runtime Persist Extension to a Curated Persist Default"), I
    want existing primitives I can compose, so that I don't have to
    extend the signature of an existing verb.

## Implementation Decisions

- **New verbs live in `lib/impermanence-common.sh`**, not a new file.
  The file is already the shared seam between install and runtime; the
  Persist vocabulary is a sub-concept of Impermanence and splitting
  would fragment related logic.
- **Verbs are named `persist_*`**; low-level writers keep their
  existing `imp_*` prefix. The prefix difference signals level of
  abstraction (orchestrators vs primitives).
- **Verbs omit data movement** (per ADR 0009). Data ops are separate
  helpers. Bundling data movement into the verbs would force a
  `mode=install|runtime` knob on `persist_apply` and a
  `move_back=yes|no` knob on `persist_unapply`, each context-dependent.
- **`persist_apply` accepts a `<kind>` argument** (`d` or `f`)
  determining the tmpfiles entry shape (`d %s 0755` vs `f %s 0644`).
  Callers either know the kind (curated lists) or detect it from disk
  (runtime tool).
- **`persist_apply` reload/start is optional**. Install-time skips
  systemd reload (the system is not running). Runtime always reloads
  and starts. Implemented as a flag, an env var, or by splitting into
  `persist_apply` (write only) + `persist_activate` (reload + start) —
  implementer's choice, document the chosen shape.
- **Host-config declaration stays in the runtime tool**, not in the
  verbs. Verbs operate on `/persist` and `/etc/systemd/system`; the
  tool's CLI is the only consumer that edits host config jsonc.
- **`tools/impermanence.sh` shrinks** to: CLI parsing, host-config
  jsonc edits, status/diff reporting, and `persist_*` composition.
  The `_impermanence_*` helpers that duplicate verbs are removed.
- **`lib/chroot/impermanence.sh` shrinks**: its `_impermanence_write_*`
  family covering mount units, tmpfiles, and data movement collapses
  into `persist_apply` + `persist_stage_in_move` calls in a loop.
- **Migration is behavior-preserving**. The install-time output (units
  written, snapshots taken, data moved) must be byte-identical before
  and after for the same inputs. The runtime tool's CLI surface is
  unchanged.

## Testing Decisions

Good tests here exercise the verbs against a temp-dir filesystem and
assert observable outputs (unit file content, tmpfiles entries, file
layout on disk). They do not assert how the verbs are sequenced
internally.

- **`persist_apply` / `persist_unapply` tests** — for each verb: write
  to a temp `ROOT`, assert the unit file is at the expected path with
  the expected content; assert the tmpfiles entry is present;
  unapply and assert both are gone. Idempotency: calling `apply`
  twice produces the same end state; calling `unapply` on a
  non-existent target is a no-op. Prior art:
  `tests/chroot-impermanence.bats`, `tests/impermanence-tool.bats`.
- **Data-staging helper tests** — for each helper: set up a fake live
  path and a fake `/persist` under a temp `ROOT`; invoke; assert file
  contents and existence on both sides. Cover the `mv` vs `cp`
  asymmetry as separate test cases. Prior art: `impermanence-tool.bats`.
- **Install-time integration** — `tests/chroot-impermanence.bats`
  already exercises `impermanence_apply`. The refactored function
  must produce the same observable outputs (datasets, units,
  snapshots, file layout). The test file should pass without
  modification.
- **Runtime tool integration** — `tests/impermanence-tool.bats`
  already exercises `cmd_add`, `cmd_remove`, `cmd_status`,
  `cmd_apply_defaults`. The CLI surface and outputs are unchanged;
  the test file should pass without modification.

Tests do not assert which file a function lives in or whether
internal helpers are inlined or extracted.

## Out of Scope

- Renaming `imp_*` writers to `persist_*` for full prefix consistency.
  Decided against in the `/grill-with-docs` session — keeps the
  level-of-abstraction signal in the prefix.
- Changing the Curated Persist Defaults list itself. That is owned by
  `lib/impermanence-common.sh::CURATED_FILES` / `CURATED_DIRS` and is
  not modified here. (See `curated-defaults-fold-in` PRD for a related
  but separate refactor.)
- Closing the v1 leak documented in the **Pacman Resnapshot Hook**
  CONTEXT entry (pre-pacman drift survives one reboot). That requires
  a new pre-transaction hook; out of scope.
- Adding a new verb to `tools/impermanence.sh` (e.g. "promote
  extension to default"). This PRD enables it but does not implement
  it.
- The Install Config / Install State refactor (separate PRD:
  `config-modules-refactor`).
- The validation curated fold-in (separate PRD:
  `curated-defaults-fold-in`).

## Further Notes

ADR 0009 records the verbs-omit-data-movement decision. The Persist
Mount entry in `CONTEXT.md` was updated to document the
install-`mv` / runtime-`cp` asymmetry. Both are load-bearing for this
refactor — the verb split is what makes those semantics legible at
call sites.

After this PRD lands, the impermanence area has two clean seams:

- `impermanence-common.sh` owns Persist Mount verbs + curated lists +
  low-level writers (shared by install + runtime).
- `lib/chroot/impermanence.sh` owns install-time orchestration
  (dataset creation, snapshot, rollback hook, pacman hook).
- `tools/impermanence.sh` owns the runtime CLI.

No further structural changes anticipated in this area.
