# Host Core carries packages; apply the curation

Status: ready-for-agent

## Parent

.scratch/layered-software-model/PRD.md
Data: .scratch/layered-software-model/CURATION.md — the authoritative
per-package layer assignments. Work from its `layer` column.

## What to build

Make Host Core a real base and reduce the host profiles to deltas.

Host Core gains a `packages` object (`repo` + `aur`, both Categorized Lists),
amending ADR 0007 — whose "the lists are machine-specific" premise is exactly
what this rejects. It takes the 61 packages both machines share. `hosts/desktop`
keeps 34 as its delta. **`hosts/laptop` ends up with no packages block at all**,
because it is a strict subset of desktop — 57 repo packages in both, zero unique
to laptop. That is the confirmation the two-layer model fits this fleet, so
treat it as an acceptance criterion rather than a curiosity.

The three VM fixtures declare `packages.inherit: false`, keeping test installs
lean without an exclude list that would need updating every time Host Core grows.

`users/core` gains a real `programs` list (`docker`, `virt-manager`), and the
two throwaway test users get `programs_exclude` for both — they exist to
exercise the system install path, not user program installs.

Six packages move to derived rather than declared: the filesystem tools and
login shell already were, and the audio stack joins them — the derived PipeWire
set gains the three packages currently declared by hand alongside it. The login
shell default changes from `/bin/bash` to `/bin/zsh`, with root staying
`/bin/bash` per ADR 0054.

CURATION.md carries the full reasoning per package (R1–R21), including the
`pactree` dependency audit that dropped six entries already supplied by
something else, and the catppuccin purge.

## Acceptance criteria

- [ ] Host Core declares `packages.repo` and `packages.aur`
- [ ] `hosts/laptop` has no packages block
- [ ] `hosts/desktop` declares only its 34 delta packages
- [ ] The three VM fixtures declare `packages.inherit: false`
- [ ] `users/core` declares its programs; the two test users exclude them
- [ ] The derived audio set covers the three hand-declared packages
- [ ] The default login shell is `/bin/zsh`; root remains `/bin/bash`
- [ ] Every package marked `drop` in CURATION.md is gone from every profile
- [ ] Every package marked `derive` is declared nowhere
- [ ] Regression tests resolve the committed `core`, `desktop` and `laptop`
      profiles end-to-end and assert the final package sets
- [ ] A test asserts no Program name appears in any package list
- [ ] A test asserts no declared package duplicates something a derived set
      already provides
- [ ] The VM fixtures resolve to a lean set with no workstation userland

## Blocked by

- Exclusivity validation replaces promotion
- Layer Resolver
