# ADRs for the layered software model

Status: ready-for-agent

## Parent

.scratch/layered-software-model/PRD.md

## What to build

Three ADRs recording what landed, following the repo's existing format.

**0056 — Host Core carries packages; fixtures opt out.** Amends ADR 0007,
whose decision explicitly placed `packages` in host configs "not Host Core" on
the reasoning that the lists are machine-specific. That premise no longer
holds: `laptop` is a strict subset of `desktop`, so the shared base is real.
Records the two-layer model and `packages.inherit`.

Record the rejected alternative, because it was fully specified before being
dropped and a future reader will otherwise re-derive it: a three-tier
`core → workstation → host` model with a reserved `hosts/base/` directory and
an `extends` key supporting chaining and cycle detection. It existed solely to
keep three VM fixtures lean, and `packages.inherit: false` buys the same
outcome for one key instead of a permanent concept in daily use. The signal
that two layers fit this fleet: `hosts/laptop` ends up with no packages block
at all.

**0057 — Per-key merge classification.** Additive sets versus ordered
selections, one table shared by the installer and the menu. The context worth
capturing is that both existing rules were load-bearing where they were —
concatenation in config load, replacement in the guided view so an operator can
drop a seeded user — so neither could simply win.

**0058 — Guided package surface.** Host Core as the menu baseline rather than a
hand-copied subset, three-state provenance marking, the read-only derived
section, and the deletion of front-end-specific promotion in favour of a
config-load abort. The invariant: the same file produces the same install
through every front-end.

## Acceptance criteria

- [ ] Three ADRs exist, numbered 0056–0058, following the repo's format
- [ ] 0056 states it amends ADR 0007 and says why the original premise failed
- [ ] 0056 records the rejected three-tier model and the reason
- [ ] 0057 explains why neither existing merge rule could win outright
- [ ] 0058 states the same-file-same-install invariant
- [ ] CONTEXT.md is updated: Host Core, Host Package List, Guided Installer, and
      System Program entries reflect the new model
- [ ] CONTEXT.md gains entries for the Layer Resolver and Package Resolver
- [ ] The "base packages vs core packages" flagged ambiguity in CONTEXT.md is
      updated — ADR 0007's resolution no longer applies

## Blocked by

- Layer Resolver
- Host Core carries packages; apply the curation
- Menu reads Host Core via the Layer Resolver
