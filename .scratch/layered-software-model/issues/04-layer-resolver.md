# Layer Resolver

Status: ready-for-agent

## Parent

.scratch/layered-software-model/PRD.md
ADR: 0057 (to be written — see ticket "ADRs for the layered software model")

## What to build

One pure module that answers "given Host Core and a host profile, what is the
effective set?" — and the same for User Core and a user profile.

Today two different merge rules are in use and **both are load-bearing where
they are**. The config-load path concatenates every array, which is harmless
only because Host Core is nearly empty; the moment it carries content, a Core
`options.kernel` of `["lts"]` plus a host wanting `["zen"]` yields both kernels,
each built against ZFS DKMS. The guided effective view replaces arrays instead,
which is deliberate — it is what lets an operator drop a seeded user or switch
kernels — but it means the menu shows a different set from what installs.

So the rule cannot be global either way. It is per-key, classified by
**unordered set versus ordered selection**:

- **Additive** — concat, dedupe, and `exclude` subtracts: `packages.repo.*`,
  `packages.aur.*`, `system_programs`, `users`, `persist.directories`,
  `persist.files`, `sysctl` (deep merge), and on the user side `groups`,
  `programs`, `ssh_authorized_keys`.
- **Replace** — the later layer wins outright: `options.kernel` (element 0 is
  the Primary Kernel), `system.locale` and `system.keymap` (element 0 is the
  default), `environment.desktop`, `environment.gpu`,
  `options.mirror_countries` (ordered preference), `storage_groups[]` and
  `data_pools[]` (positional), and every scalar.

The module also owns exclusion and opt-out. Layers fold in order and the last
layer wins, so a host may re-add something a lower layer excluded. New schema
keys: `packages.exclude[]` and `system_programs_exclude[]` on a host profile,
`programs_exclude[]` on a user profile, and `packages.inherit` (bool, default
true) which is scoped to packages only — a fixture opting out still inherits
Host Core's users and sysctl.

Pure: JSON in, JSON out, no filesystem, no TTY. The config-load path adopts it
here; the guided view is rewired in a later ticket.

## Acceptance criteria

- [ ] Additive keys concatenate and dedupe across layers
- [ ] Replace keys are overwritten wholesale by the later layer
- [ ] Every key in the classification table is covered by at least one test
- [ ] `exclude` removes an entry the lower layer contributed
- [ ] A later layer can re-add something an earlier layer excluded
- [ ] `packages.inherit: false` yields no inherited packages
- [ ] A profile with `packages.inherit: false` still inherits users and sysctl
- [ ] The new keys are registered in the closed schema
- [ ] An unknown key still aborts with its path (ADR 0036)
- [ ] The config-load path resolves through this module
- [ ] Committed profiles resolve to the same sets as before this change

## Blocked by

- Collapse the package slots
