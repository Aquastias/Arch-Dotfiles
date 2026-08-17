# Migrate the Host Program wire format

Status: ready-for-agent

## Problem Statement

ADR 0084 renamed the concept **System Program → Host Program** in prose, code
comments, Display Labels, and messages — but deliberately left the machine
surfaces untouched. So today a profile author reads "Host Program" everywhere in
the docs and glossary, then opens a `profile.jsonc` and must type
`system_programs`; a program author reads the [[Host Program]] glossary entry,
then marks a program `"system": true`. The term and the token disagree. The
[[Host Program]] entry documents this on purpose and points here. The mismatch
is a standing papercut: it confuses new authors, invites "is this the same
thing?" doubt, and leaves "system" — already the most overloaded word in the
repo — alive in exactly the place the rename was meant to clean up.

## Solution

Complete the rename by migrating the wire format so the identifiers match the
vocabulary. The Host Profile field becomes `host_programs` (and its control key
`host_programs_exclude`); the per-program kind marker becomes a `kind` enum
(`"host" | "user"`); and the [[Program Registry]]'s `program_kind` reports
`host` instead of `system`. It is a **hard cutover**: the old keys are not
aliased — because the closed schema aborts on any unknown key, a stale
`system_programs` / `"system"` now fails loudly at load, which is the desired
outcome. Every in-repo profile and program config is migrated in the same
change, so the repo stays internally consistent and the term finally means one
thing at every layer. The rename is behaviourally inert at the resolved level:
what lands on a machine does not change.

## User Stories

1. As a Host Profile author, I want to declare root/pacman programs under a
   `host_programs` key, so that the field I type matches the "Host Program"
   term I read in the glossary.
2. As a Host Profile author, I want to drop an inherited Host Program via
   `host_programs_exclude`, so that the exclusion control key reads
   consistently with the field it subtracts from.
3. As a Host Core maintainer, I want core's shared Host Programs expressed as
   `host_programs`, so that the base layer speaks the same vocabulary as every
   host delta.
4. As a Program author, I want to mark a program `"kind": "host"` or
   `"kind": "user"`, so that a program's nature is stated positively instead of
   a `"system": false` double-negative that means "user".
5. As a Program author, I want an absent or misspelled `kind` to abort at
   registry build with an actionable message, so that a mis-authored program
   config never silently resolves to the wrong slot.
6. As an installer developer, I want `program_kind` to return `host | user |
   none`, so that call sites read `== "host"` and match the domain term.
7. As an installer developer, I want `program_names_of_kind host` to enumerate
   Host Programs, so that the Program Registry query mirrors the glossary.
8. As a Guided Installer operator, I want the host-program picker and its
   Display Label to say "host programs", so that the menu matches the docs.
9. As a Guided Installer operator, I want a typed extra-package that resolves to
   a Host Program routed into `host_programs`, so that routing-by-kind at entry
   time stays correct under the new names.
10. As a Guided Installer operator, I want Save Profile / Export to emit
    `host_programs`, so that the artifacts a session writes use the migrated
    field.
11. As a profile author relying on layering, I want the [[Layer Resolver]] to
    treat `host_programs` as the additive key (concat + dedupe, `exclude`
    subtracts), so that host-over-core merge behaviour is preserved under the
    new name.
12. As a user-profile author, I want a user program that references a Host
    Program to reconcile exactly as before (shadow / no-op / abort), so that the
    ADR 0036 reconciliation rules survive the rename.
13. As a profile author, I want a `requires` dependency satisfied by a Host
    Program to keep its ordering guarantee, so that ADR 0065 dependency ordering
    is unaffected.
14. As a Guided Installer operator, I want the Printing / Bluetooth / Power
    toggle-derived Host Programs injected into `host_programs` at assembly time,
    so that ADR 0079/0080 injection still lands in the right field.
15. As an operator running the Package Resolver / `explain-packages`, I want
    derived Host Programs reported under the migrated vocabulary, so that the
    inspector and the config stay in agreement.
16. As a maintainer, I want a profile still using the retired `system_programs`
    or `"system"` key to abort at load naming the offending path, so that the
    hard cutover is enforced, not merely documented.
17. As a maintainer, I want the combination-matrix registry entry renamed to
    `host_programs`, so that matrix-driven tooling references the live key.
18. As a future reader, I want the [[Host Program]] glossary entry updated to
    state the field is `host_programs` (deferral resolved), so that the
    documented term/token gap is closed.
19. As a future reader, I want a new ADR recording this migration — the `kind`
    enum choice and the no-alias cutover — that resolves ADR 0084's deferral,
    so that the decision trail is complete.
20. As a VM-fixture maintainer, I want the committed VM host profiles migrated
    to the new keys, so that the fixtures load under the closed schema.

## Implementation Decisions

- **Host Profile field.** `system_programs` → `host_programs`;
  `system_programs_exclude` → `host_programs_exclude`. The closed-schema
  allowed-key tables that gate profile load are updated so the new keys are
  accepted and the old ones fall through to the existing unknown-key abort.

- **Per-program kind marker.** The `"system": true|false` bool is replaced by a
  `"kind": "host" | "user"` enum in every Program Config. Chosen over a
  `"host": true|false` bool because a bool whose `false` means "user"
  re-introduces the exact false-name smell ADR 0084 removed, and an enum mirrors
  `program_kind`'s existing string return. `kind` is **required**: an absent or
  out-of-set value aborts at [[Program Registry]] build with an actionable
  message.

- **Program Registry / `program_kind`.** The registry maps each program name to
  its `category/name` path and its `kind`. `program_kind <name>` returns
  `host | user | none` (was `system | user | none`); `program_names_of_kind`
  takes `host | user`. All comparison sites move from `== "system"` to
  `== "host"`.

- **Layer Resolver.** The additive-key classification table lists
  `host_programs` (was `system_programs`); additive merge, dedupe, and the
  `host_programs_exclude` subtraction behave exactly as before. The control key
  is still stripped from resolved output.

- **Toggle-derived injection.** The Printing / Bluetooth / Power assembly step
  injects derived Host Programs into `.host_programs` (was `.system_programs`).
  The Program directories and their `install.sh` are untouched.

- **Guided Installer.** The menu field key and its Display Label move to
  `host_programs`; the kind-filtered host-program picker offers `kind: host`
  programs and the User Editor picker `kind: user`; entry-time routing sends a
  typed Host Program name to `host_programs`; Save/Export emit `host_programs`.

- **In-repo data migrated in the same change.** Host Core, all Host Profiles
  (desktop, laptop), the committed VM host profiles, and all Program Configs are
  rewritten to the new keys/enum. Any bats fixtures declaring the old keys move
  too.

- **Hard cutover, no alias.** No back-compat shim. The closed schema's
  unknown-key abort is the migration's enforcement mechanism.

- **Docs.** The [[Host Program]] glossary entry is updated to state the field is
  `host_programs` (deferral resolved) and every `system_programs` mention across
  the glossary follows. A new ADR records the migration (the `kind` enum, the
  no-alias cutover) and marks ADR 0084's deferral resolved. Historical ADRs stay
  verbatim.

- **Out-of-band identifiers (optional, non-behavioural).** Internal function and
  variable names still carrying "system" (e.g. the guided add-host-program
  helper, local `sys_progs` arrays) may be renamed for consistency but are not
  wire format, are not asserted by any test, and are not required for the
  cutover.

## Testing Decisions

- **What makes a good test here:** assert external behaviour only — feed
  profiles and program configs carrying the new identifiers and assert the
  resolved Effective Config, the kind filtering, the toggle injection, the
  reconciliation outcome, and the resolver report. Never assert internal
  function names or the shape of intermediate state. Old-name behaviour is
  asserted through its user-visible consequence: a load-time abort.

- **Seams — reuse, add none.** The migration rides entirely on the existing
  pure-module bats suite; each is updated to the new identifiers rather than
  duplicated:
  - Layer Resolver additive merge + `exclude` of the host-programs field.
  - Config load / layered profiles: kind resolution and the ADR 0036 user →
    Host Program reconciliation (shadow / no-op / abort).
  - `requires` ordering satisfied by a Host Program (ADR 0065).
  - Guided pickers: kind-filtered offering, entry-time routing, and emit of
    `host_programs`.
  - Printing / Bluetooth / Power toggle-derived injection into `host_programs`.
  - Package Resolver / `explain-packages` derived-report vocabulary.

- **One new regression assertion (not a new seam):** a profile carrying the
  retired `system_programs` key, and a program config carrying the retired
  `"system"` flag, each abort at load naming the offending path. Prior art: the
  existing closed-schema unknown-key abort assertions in the profile-loader
  suite, and the additive-merge assertions in the layer-resolver suite.

## Out of Scope

- The `.os/programs/system/` **category** directory (bluetooth,
  power-profiles-daemon, tuned). It is an orthogonal, cosmetic category label,
  not the kind axis; renaming it was ruled out during the ADR 0084 grilling and
  stays out here.
- The already-completed prose rename (ADR 0084): the human term "Host Program"
  in comments, Display Labels, and messages is done and is not revisited.
- Any change to *how* a Host Program installs — root/pacman in the chroot phase,
  before user programs — is unchanged; this is a naming migration only.
- A VM-level integration seam. The pure-module coverage is sufficient; a heavy
  `.os/tests/vm` profile is not added.
- Other `system` surfaces that are not the Host Program kind axis: the profile
  `system` block (hostname/locale/timezone/keymap) and the Guided **System**
  Configuration Category keep their names.

## Further Notes

- The change is behaviourally inert at the resolved level — the same packages
  land on the same machines — so the risk is breadth, not depth: a wide,
  mechanical diff across schema, resolver, assembly, guided, matrix, every
  committed profile, and every Program Config, all landing atomically because
  the closed schema will reject any file the migration misses.
- Because the cutover is hard, the safest execution order is: add the new keys
  to the schema and resolver first, migrate all data, then remove old-key
  acceptance — but the end state is a single vocabulary with no alias.
