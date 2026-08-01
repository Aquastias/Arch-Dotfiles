# Read-only derived section

Status: done

## Parent

.scratch/layered-software-model/PRD.md
ADR: 0058 (to be written)

## What to build

Close the last gap where the menu under-reports the install.

Even with the declared packages editable, a large set arrives without appearing
anywhere: the KDE adapter's Plasma shell and applications plus its own AUR
list, GPU drivers from GPU Resolution, the auto-derived audio stack, the
Security and Backup Extras routed through the Primary User's paru pass, and
`sops` when the host or a user ships secrets.

Add a read-only `derived` section to the Packages screen listing what the
current choices pull in, grouped by source. It calls the same Package Resolver
as the CLI inspector, so the two cannot drift.

Not toggleable, deliberately. ADR 0021 gives the DE adapter ownership of its
own package set, and these are consequences of choices already made elsewhere
in the menu — Environment, Security, Backup. The section should say so, so the
operator knows where to go to change them.

## Acceptance criteria

- [ ] The Packages screen has a `derived` section
- [ ] Sources are listed separately: KDE shell, KDE apps, GPU, audio, security,
      backup, sops
- [ ] Each source shows its package count and drills to the list
- [ ] Entries cannot be toggled
- [ ] The section names which category drives each source
- [ ] Changing the GPU vendor updates the section
- [ ] Changing the desktop selection updates the section
- [ ] Toggling a security or backup tool updates the section
- [ ] The section and the CLI inspector agree for the same config

## Blocked by

- Package Resolver + explain-packages
- Guided Packages screen
