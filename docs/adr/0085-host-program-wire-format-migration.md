# Migrate the Host Program wire format (`system_programs` → `host_programs`)

ADR 0084 renamed the concept **System Program → Host Program** in prose but
deliberately deferred the wire format, leaving a term/token gap: the docs said
"Host Program" while a profile declared `system_programs` and a program config
carried `"system": true`. This ADR completes the rename in the machine surfaces.
The Host Profile field becomes **`host_programs`** (control key
`host_programs_exclude`); the per-program marker becomes a **`"kind"` enum**
(`"host" | "user"`), required, aborting at [[Program Registry]] build when absent
or out of set; and `program_kind` now reports `host | user | none`. The change is
behaviourally inert — the same packages land on the same machines.

## Considered options

- **`"kind": "host" | "user"` enum** (chosen) over a **`"host": true|false`
  bool** — a bool whose `false` means "a user program" reintroduces the exact
  false-name smell ADR 0084 removed, and an enum mirrors `program_kind`'s
  existing string return. Same blast radius across the 18 program configs.
- **Hard cutover, no alias** (chosen) over a **back-compat shim that accepts the
  old keys** — the closed schema already aborts on unknown keys, so the retired
  `system_programs` / `"system"` now fail loudly at load, which is the desired
  enforcement. A shim would soften the closed-schema contract and leave two
  live names. All in-repo profiles and program configs were migrated in the same
  change, so nothing depends on the old names.
- **Rename the `.os/programs/system/` category too** — rejected (unchanged): the
  category label is orthogonal to the kind axis (ADR 0084's grilling already
  ruled it out), and categories are cosmetic.

## Consequences

- Two regression assertions lock the cutover: a profile carrying
  `system_programs` / `system_programs_exclude`, and a program config carrying
  `"system"`, each abort at load naming the offending path.
- Historical ADRs (0079, 0080, 0084, …) keep saying "System Program" and
  `system_programs` verbatim — they are point-in-time records. The [[Host
  Program]] glossary entry is the bridge, now stating the field is
  `host_programs` with this ADR as the reference.
- The internal helper identifiers were all renamed to the host vocabulary for
  consistency (`edit_append_host_programs`, `_guided_add_host_program`,
  `_ctl_host_program_names`, `_profiles_install_host_program`) even though they
  are non-behavioural: renaming exactly one of them would have been the harder
  inconsistency to justify. `validate_program`'s expected-kind parameter also
  moved from a `true|false` bool to the `host|user` enum, so no bool↔enum
  straddle survives in the validator signature.
