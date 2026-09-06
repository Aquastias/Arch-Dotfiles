# Program `conflicts`: declared mutual exclusion, enforced before side effects

A Program's `config.jsonc` may declare **`conflicts: ["ufw", …]`** — other
Programs it cannot coexist with (e.g. firewalld vs ufw). The relation is
enforced in `validate_install_context` (`_validation_check_conflicts`), the
single pre-side-effect validation seam, so a selection that lands two mutually
exclusive programs on one machine **aborts up front** with an actionable message
instead of one installing + enabling and the other detonating part-way through.

The check runs over the **combined set that reaches a user's machine** — the
Host Programs plus that user's own `programs` — mirroring how `requires` already
folds host programs in (ADR 0065). This catches the host-firewall vs
user-firewall case, not just two rivals in one user's list.

The relation is **symmetric**: declaring `conflicts` on *one* side is enough.
The validator scans every present program's declared conflicts against the
present set, so `ufw → firewalld` fires whether ufw, firewalld, or both declare
it. A mutual declaration and the two directions of one pair collapse to a single
unordered-pair message.

This replaces an **implicit, runtime-only exclusion**: `ufw`/`firewalld`
`install.sh` each `command_exists`-guard against the other at their top and
`exit 1` if found. But that fires *during* the install — after the first
firewall's package is installed and its service enabled — leaving a half-done
"one firewall live, install aborted" state, the exact class of expensive,
part-way failure ADR 0065 exists to prevent. The runtime guards stay as
defense-in-depth for manual/partial runs, but are no longer the first line of
defense.

## Considered Options

### Enforcement
- **Declared `conflicts` + fail-fast validation** — chosen. A machine-readable
  relation, checked at the existing config-validation seam before any disk is
  touched. Generic: any program declares its rivals; the guided front-end,
  `--profile`, and VM seed all abort identically.
- **Keep the runtime `command_exists` guard only** — rejected. It fires after
  the first program's side effects (package + enabled service) are already
  applied — the half-done failure this ADR exists to prevent.
- **Auto-drop one of the conflicting pair** — rejected. Silently discarding an
  operator's explicit selection is more surprising than a fail-fast message, and
  there is no principled rule for which one to keep.

### Declaration direction
- **Symmetric, single declaration** — chosen. Requiring both sides to declare is
  redundant and drift-prone: one could list the other and not vice versa,
  silently half-protecting. The validator treats a conflict from either side as
  authoritative.

## Consequences

- `config.jsonc`'s closed schema (ADR 0036) gains `conflicts[]`; an unknown-key
  abort still guards typos elsewhere.
- The check is pure over `INSTALLER_DIR` + two JSON arrays (host programs, the
  user's programs) and unit-tested (`tests/config/validation-conflicts.bats`):
  declared reads, symmetry, mutual-declaration de-dup, host-program presence,
  rival-absent, clean pass.
- `firewalld` and `ufw` declare `conflicts` as the seed consumers; their runtime
  guards remain.

## Status

accepted — extends ADR 0036 (closed-schema config, program contracts); sibling
to ADR 0065 (`requires` dependency ordering)
