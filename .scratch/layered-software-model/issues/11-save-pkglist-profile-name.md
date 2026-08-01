# save-pkglist takes a profile name

Status: ready-for-agent

## Parent

.scratch/layered-software-model/PRD.md

## What to build

`save-pkglist.sh` has been broken since ADR 0020 decoupled a profile's name
from the machine's hostname. It writes to a directory derived from
`$(hostname)` — `eterniox`, `chronos` — while the profile directories are named
`desktop` and `laptop`, so it exits with "No host dir" every time. Its
counterpart `install-pkglist.sh` reads the files it never wrote.

Make it take a **profile** name, defaulting sensibly, so it works again.

Second problem: it writes a flat `pacman -Qqen` dump. Under the layered model
that cannot round-trip — replaying it into a profile would collapse Host Core,
the host delta and every derived set into one host's list, undoing the layering
on first use. Keep it as a drift-recovery artifact and stamp the output as
such, so it is used to diff rather than to author. A profile-aware version that
emits only the genuine host delta is possible but is separate work.

## Acceptance criteria

- [ ] The tool takes a profile name and writes into that profile's directory
- [ ] Running it for `desktop` and `laptop` succeeds
- [ ] An unknown profile name fails with an actionable message
- [ ] Each output file carries a header marking it a drift snapshot and warning
      against replaying it into a profile
- [ ] `install-pkglist.sh` reads the same location
- [ ] The tools' documented behaviour matches what they do

## Blocked by

None — can start immediately.
