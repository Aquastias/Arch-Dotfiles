# Menu reads Host Core via the Layer Resolver

Status: ready-for-agent

## Parent

.scratch/layered-software-model/PRD.md
ADR: 0058 (to be written)

## What to build

Stop the menu lying about what will be installed.

Two defects combine today. The guided baseline **hand-copies** a handful of
Host Core's values rather than loading Host Core, so anything in core that was
not copied is invisible — `cups` installs on every host and appears nowhere in
the menu. And the menu's effective view merges arrays by replacement while the
installer concatenates, so seeding from `desktop` displays
`system programs: grub` while the install actually produces `["cups", "grub"]`.

Load the baseline from Host Core, and route the effective view through the
Layer Resolver so display and install cannot disagree. Host Core's contents
then surface as seeded-but-unmarked rows: present and checked, with no override
dot, because the operator has not touched them.

Save Profile writes a plain delta over Host Core.

This is the fix for the original report — "if I choose a profile containing
system level programs, these do not appear selected in the menu". The root
cause turned out to be the inverse of the symptom: profile programs *do* mark
correctly; it is **core** programs that are invisible, and the merge that
under-reports.

## Acceptance criteria

- [ ] The guided baseline is loaded from Host Core, not hand-copied
- [ ] `cups` renders as a selected System Program with no override dot
- [ ] Seeding `desktop` shows `cups, grub`, matching what installs
- [ ] The menu's effective view and the installer produce the same set for the
      same config
- [ ] A value seeded from core carries no override dot until edited
- [ ] Save Profile writes a delta over Host Core
- [ ] Editing a core-inherited value marks it as an override

## Blocked by

- Layer Resolver
- Host Core carries packages; apply the curation
