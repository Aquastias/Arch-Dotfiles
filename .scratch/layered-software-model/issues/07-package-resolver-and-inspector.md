# Package Resolver + explain-packages

Status: ready-for-agent

## Parent

.scratch/layered-software-model/PRD.md

## What to build

One command that answers "what actually lands on this machine?".

There are eighteen distinct paths by which a package reaches the system. Five
are authored, the rest are derived from a setting the operator already made.
No amount of slot-collapsing removes the derivation — GPU drivers *should* be
computed rather than hand-listed — so the answer is not fewer paths but a way
to **query** the result.

Build a pure resolver: Effective Config in, every package out, each tagged with
its source and layer. It covers the authored slots, the Base Package List, and
every derived set — kernel and headers, bootloader, GPU drivers, audio,
filesystem tools, login shell, the Plasma shell, KDE applications, KDE AUR,
Security & Backup Extras, and secrets-activated sops. Every input is
declarative, so it needs no pacman query and stays testable headless.

On top of it, a CLI inspector that takes a profile name and prints the resolved
set grouped by source, with a total and the excluded entries listed separately.
It must work on a **hand-edited** profile without launching the installer —
that is the whole point.

The same resolver backs the menu's read-only derived section in a later ticket,
so the two can never drift.

## Acceptance criteria

- [ ] The resolver returns every package with its source and layer
- [ ] Authored slots, the Base Package List and all derived sets are covered
- [ ] Changing the GPU vendor changes the resolved driver set
- [ ] Changing the desktop selection changes the audio and Plasma sets
- [ ] Changing the filesystem changes the filesystem-tool set
- [ ] Changing a user's login shell changes the shell package
- [ ] Changing the bootloader changes the bootloader package
- [ ] Excluded packages are reported separately and absent from the installed set
- [ ] The resolver is deterministic for a given config
- [ ] The resolver makes no pacman or network call
- [ ] The CLI takes a profile name and prints the set grouped by source
- [ ] The CLI works on a hand-edited profile with no TUI involvement
- [ ] The CLI reports a total count and the excluded entries

## Blocked by

- Program kind is authoritative
- Layer Resolver
