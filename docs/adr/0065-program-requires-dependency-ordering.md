# Program `requires`: declared dependency, enforced before side effects

A Program's `config.jsonc` may declare **`requires: ["podman", …]`** — other
Programs whose install-time *setup* (the package **and** its side effects, e.g.
podman's subuid/subgid + linger) must already be in place when it runs. The
dependency is enforced in `validate_install_context`
(`_validation_check_requires_order`), the single pre-side-effect validation
seam, so a list that omits a dependency or orders it after the dependent
**aborts up front** with an actionable message instead of hard-failing part-way
through the install.

A required program is satisfied when it is a **host system program** (installed
before every user program) or appears **earlier in the same user's program
list** (the Runner installs a user's programs one-by-one in declared order).
Both readings match how the Runner actually sequences installs, so the check
neither over- nor under-approximates.

This replaces an **implicit, unenforced ordering contract**: searxng's
`install.sh` hard-failed with "podman must be installed before searxng" if the
podman package was absent, and the only thing guaranteeing order was the
hand-maintained `.programs` array. The guided installer stores a user's programs
in **toggle order**, which silently placed searxng before podman and detonated
mid-install — the concrete failure that motivated this. The searxng `install.sh`
package guard stays as defense-in-depth for manual/partial runs, but is no
longer the first line of defense.

## Considered Options

### Enforcement
- **Declared `requires` + fail-fast validation** — chosen. A machine-readable
  dependency, checked at the existing config-validation seam before any disk is
  touched. Generic: any program can declare dependencies; the guided front-end,
  `--profile`, and VM seed all abort identically.
- **Auto-order the install (topological sort)** — rejected. Spares the operator
  the ordering, but silently reshuffles a declared list; a wrong/omitted
  dependency would still need a hard error, and "it just worked differently than
  written" is harder to reason about than a fail-fast message.
- **Keep the runtime guard only** — rejected. It fires *during* the install,
  after users/other programs are already created — the expensive, half-done
  failure this ADR exists to prevent.

## Consequences

- `config.jsonc`'s closed schema (ADR 0036) gains `requires[]`; an unknown-key
  abort still guards typos elsewhere.
- The check is pure over `OS_DIR` + two JSON arrays (system programs, the user's
  programs) and unit-tested (`tests/config/validation-requires.bats`): declared
  reads, good/bad order, missing dependency, system-program satisfaction.
- Only searxng declares `requires` today (`["podman"]`); the committed
  `aquastias` profile already ordered them correctly, so it validates unchanged.

## Status

accepted — extends ADR 0036 (closed-schema config, program contracts)
