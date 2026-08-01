# Per-key merge classification: additive sets vs ordered selections

---
Status: accepted
---

Layer resolution is **per-key**, classified by **unordered set versus ordered
selection**, and the single classification table is shared by the installer and
the Guided Installer's menu. It lives in one pure module — the **Layer
Resolver** (`lib/config/layer-resolver.sh`) — so display and install cannot
disagree about what is installed.

## Why neither existing rule could simply win

Two different merge rules were in use, and **both were load-bearing where they
were**. That is the whole difficulty: this was not one correct rule and one
bug.

**The config-load path concatenated every array.** Harmless only because Host
Core was nearly empty — it declared one System Program and a swappiness value.
The moment core carries real content (ADR 0056), a core `options.kernel` of
`["lts"]` plus a host wanting `["zen"]` yields **both** kernels, each built
against ZFS DKMS. Concatenation is right for `packages.repo`; it is incoherent
for a kernel selection.

**The guided effective view replaced arrays.** Also deliberate: it is what lets
an operator drop a seeded user or switch kernels in the menu. But it meant the
menu displayed a different set from what installed — seeding `desktop` showed
`system programs: grub` while the install produced `["cups", "grub"]`.

Making either global would have broken the case the other was serving. So the
rule is per-key.

## The classification

**Additive** — concat, dedupe, and `exclude` subtracts. Membership is what
matters, order does not, and a lower layer contributing is a feature:

`packages.repo.*`, `packages.aur.*`, `system_programs`, `users`,
`persist.directories`, `persist.files`, `sysctl` (deep merge), and on the user
side `groups`, `programs`, `ssh_authorized_keys`.

**Replace** — the later layer wins outright. Position carries meaning, or the
value is a single choice, so merging two layers is incoherent:

`options.kernel` (element 0 is the Primary Kernel), `system.locale` and
`system.keymap` (element 0 is the default), `environment.desktop`,
`environment.gpu`, `options.mirror_countries` (ordered preference),
`storage_groups[]` and `data_pools[]` (positional), and every scalar.

Anything not listed as additive is replaced, so a new key cannot start
concatenating by accident.

## Folding

Layers fold in order and **the last layer wins**, so a host may re-add
something a lower layer excluded. Exclusions apply per fold, from the **upper**
layer only: a lower layer excluding something it never inherited is vacuous,
and applying it would stop a later layer from re-adding the entry — which would
contradict last-layer-wins.

`packages.inherit: false` is applied **first**, before the fold, so a fixture
opting out never has to exclude what it never wanted. It is scoped to packages
(ADR 0056).

The control keys — `packages.exclude`, `packages.inherit`,
`system_programs_exclude`, `programs_exclude` — are stripped from the resolved
output. They are instructions to the resolver, not content, and must never
reach a consumer or a saved profile.

## Purity

The Layer Resolver is JSON in, JSON out: no filesystem, no TTY, no globals.
That is deliberate — it makes the layering contract testable without a VM, and
it is what lets the menu and the installer call the *same* code rather than two
implementations that agree by inspection.

## Consequences

- One table to change when a key's semantics change; two consumers follow.
- The menu's effective view and the emitted Effective Config are the same
  computation, so the class of bug where the menu under-reports the install is
  closed structurally rather than by a matching pair of fixes.
- Save Profile subtracts Host Core through the inverse of this fold
  (`guided_core_delta`), so a saved profile stays a delta and round-trips:
  `layer_resolve(core, saved_delta)` reproduces what the operator saw.
