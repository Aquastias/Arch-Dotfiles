# ADR 0011: Shell commons as default for Program Install Scripts

## Status
Accepted

## Context
Every Program Install Script (`.os/programs/<category>/<name>/install.sh`)
runs inside `arch-chroot` via the Program Runner (`lib/run-program.sh`),
which sources the Shell Stdlib (`lib/shell-stdlib.sh`) once before
sourcing the install.sh. So every program script inherits the stdlib
helpers without its own `source` line.

Before this ADR there was no convention saying program scripts should
*prefer* the stdlib over inline bash. The stdlib also held 25 functions
of which 20 had zero callers anywhere in the tree — a sign that the
library had drifted away from real use and that nobody knew it was the
expected place to put a shared helper. Cleanup (commit 2) removed the
20 unused helpers and left five with real callers: `print_status`,
`check_root`, `send_user_notification`, `command_exists`,
`package_installed`.

Without a stated rule, the equilibrium goes the wrong way:

- A program author writes a one-off `_print()` helper inline because
  it's faster than reading `lib/shell/`.
- The next program copies the inline version, slightly different.
- Over time the stdlib's `print_status` becomes one of N near-identical
  helpers, each owned by its program, none tested, all drifting.

## Decision
Program Install Scripts prefer Shell Stdlib helpers over inline bash
when a helper exists. New shared helpers land in
`lib/shell/<module>.sh` with a matching `commons-<module>.bats` test.
A program script must not redefine a commons-named helper locally;
`tests/audit.sh` section 12 enforces this by failing the audit if any
`programs/*/install.sh` defines a function whose name collides with a
surviving commons helper.

**Scope: `.os/programs/*/install.sh` only.** Out of scope:

- `lib/*.sh` and `lib/chroot/*.sh` — these have their own ad-hoc
  `info/warn/error/section` helpers and live in a different layer of
  the install pipeline. Unifying them is a separate, larger effort.
- `tools/*.sh` — operator tooling that does not run via the Program
  Runner and does not source Shell Stdlib.
- The five empty commons modules (`strings.sh`, `arrays.sh`,
  `directories.sh`, `environments.sh`) are scaffolding for future
  helpers; nothing forces program scripts to call them.

New commons helpers land only when a real second caller demands one
— no speculative additions.

## Considered alternatives
**No convention.** Status quo before this ADR. Cheap to maintain on
day one, but the audit shows where it leads: dead library code +
inline duplicates + nothing to grep when adding a new program.

**Mandate via lint, no ADR.** A rule the audit enforces but no
written explanation leaves the next author asking "why did the audit
fail?" The ADR exists so the rule has a referenceable why.

**Force every program through every helper.** Stronger rule —
"every install.sh must call `check_root`, `print_status`, ..." —
would over-fit; some programs legitimately have no need. Prefer-when-
applicable + no-local-redefinitions is the lightest enforceable rule
that captures the intent.

## Consequences
- Program authors get a small (5-function) menu of helpers that
  *will* be present at runtime, tested per-module under
  `commons-<module>.bats`.
- A new commons helper is a three-step ritual: write it in
  `lib/shell/<module>.sh`, add a test in
  `commons-<module>.bats`, expect the audit's section-12 helper-name
  list to grow at the same time.
- Local helpers that don't collide with commons names are still fine
  — the audit only flags name collisions, not all custom functions.
- `lib/` and `tools/` are untouched; nothing in this ADR triggers a
  refactor there.
