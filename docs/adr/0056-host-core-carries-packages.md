# Host Core carries packages; fixtures opt out via `packages.inherit`

---
Status: accepted
---

**Host Core gains a `packages` object** (`repo` + `aur`, both Categorized
Lists), so software shared by every real host is declared once and each host
profile becomes a **delta**. The three VM fixtures opt out of the inherited
package set with **`packages.inherit: false`**, scoped to packages only.

This **amends ADR 0007**, which explicitly placed `packages` in host configs
"not Host Core".

## Why ADR 0007's premise failed

0007 reasoned that package lists are machine-specific, so a shared list would
be wrong by construction. Measured against the actual fleet, that is false:

- `desktop` and `laptop` declare **57 repo packages in common**.
- **Zero** packages are unique to `laptop` — it is a strict *subset* of
  `desktop`.

So both files carried the full list and the two drifted by omission rather
than by intent: `logrotate`, `fd`, `fzf`, `lazygit`, `neovim`, `imagemagick`,
`zip` and `openbsd-netcat` were on `desktop` only, with nothing
desktop-specific about any of them. The duplication was the bug 0007 was
trying to prevent, arriving by the other route.

The curation moved 61 packages into core (55 repo + 6 AUR) and left `desktop`
a 34-package delta. **`hosts/laptop` ends up with no packages block at all** —
the confirmation that the shared base is real, and the signal that two layers
fit this fleet.

## `packages.inherit`

The three VM fixtures (`arch-data`, `arch-kde`, `arch-secure`) exist to
exercise install paths, not to install a workstation. Inheriting core would
make every Tier 2 install pacstrap `steam`, `wine`, `gimp` and `firefox`.

`packages.inherit: false` drops the inherited package set wholesale. It is
**scoped to packages**: a fixture still inherits core's `users`, `sysctl` and
`system_programs`, so opting out of a package list never silently opts out of
the rest of the base.

The alternative — an `exclude` list on each fixture — was rejected because it
would need updating every time Host Core grows, which is exactly the coupling
this decision removes.

`packages.exclude[]` and `system_programs_exclude[]` survive for the real case
they serve: a machine dropping one thing core declares.

## Rejected: a three-tier `core → workstation → host` model

Fully specified before being dropped, and recorded here so a future reader does
not re-derive it.

The design added a reserved `hosts/base/` tier and an `extends` key supporting
chaining and cycle detection, with Save Profile preserving the extends chain.
Core would hold the true universals; `workstation` the GUI userland; hosts the
per-machine delta.

It existed for exactly one reason: to keep the three VM fixtures lean. That is
a test-fixture problem, and it was buying a permanent concept in daily use to
solve it — every future reader of every profile would have to know which of
three tiers a package belonged in, and Save would have to reason about a chain.

`packages.inherit: false` buys the same outcome for **one key** instead. So:
no `hosts/base/`, no `extends`, no chaining, no cycle detection, no
multi-parent resolution order. Two layers, core → host — the model already in
place before this work started.

Revisit only if a real headless or server host appears, i.e. when a third tier
would carry machines rather than fixtures.

## Consequences

- Adding a machine means listing only what is different about it.
- A package shared by both machines is edited in one place.
- `save-pkglist.sh` output is explicitly **not** replayable into a profile: a
  flat `pacman -Qqen` dump would collapse core, the host delta and every
  derived set into one list. It is stamped a Drift Snapshot for diffing.
- Six packages moved from *declared* to *derived* (the filesystem tools, the
  login shell, and three PipeWire-adjacent packages) — they were being declared
  by hand while the installer already computed them.
- `users/core` gains a real `programs` list (`docker`, `virt-manager`); the two
  throwaway test users carry `programs_exclude` for both.
