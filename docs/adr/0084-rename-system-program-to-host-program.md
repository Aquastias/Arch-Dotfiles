# Rename "System Program" to "Host Program"

The term **System Program** — a root/pacman program installed in the chroot
phase, counterpart to a per-user AUR **User Program** — was a misnomer on two
counts. Its own defining trait is being **host-owned** (declared in a host's
`system_programs`, not any user's `programs`), which "Host Program" states
directly and pairs cleanly with **User Program** (host-owned vs user-owned);
and "system" was badly overloaded in this repo (the profile `system` block, the
`"system"` flag, the `program_kind` value, the `.os/programs/system/` category,
the guided **System** category). We rename the concept to **Host Program**
across CONTEXT.md, code comments, Display Labels, and user-facing messages.

We deliberately scope this to **vocabulary only**: the wire-format identifiers
stay untouched — the `system_programs` / `system_programs_exclude` fields, the
`"system": true` flag, and `program_kind`'s `system`/`user` return values. So a
reader now meets the term "Host Program" in prose but the token `system_programs`
in JSON; the [[Host Program]] glossary entry notes this on purpose.

## Considered options

- **Predefined Program** (the original proposal) — rejected: *every* Program
  under `.os/programs/` is predefined, User Programs included, so it names the
  parent concept, not this kind. It fails to distinguish the axis at all.
- **Root Program** — viable (root/pacman is the mechanism) but describes *how*
  it installs, not *what* it is, and doesn't pair with "User Program" as
  naturally as the host/user ownership axis.
- **Rename the wire format too** (`system_programs` → `host_programs`, etc.) —
  rejected *for now*: a breaking data-format change touching every profile, the
  closed schema, resolver, validation, emit, and the Guided Installer. Decoupled
  as separate, explicitly-scheduled work; this ADR is the pointer for it.

## Consequences

- Historical ADRs (0079, 0080, …) keep saying "System Program" verbatim — they
  are point-in-time records, not rewritten. This ADR is the bridge from the old
  term to the new one.
- Because identifiers are unchanged, this rename is behaviourally inert: no
  test, schema, or profile changes. The only user-visible shift is prose and a
  handful of Display Labels / messages (e.g. the Packages preview now reads
  "host programs", the reconcile error says "is a Host Program").
