# 01: Matrix cell zfs-single-plain runs out of disk during AUR builds

**What to build:** `matrix.sh run zfs-single-plain` installs the full
`eterniox` fleet profile (KDE, gaming, dev, AUR) onto a 40G VM disk. On
2026-10-10 the install died in the Runner's paru pass: `No space left on
device` from line 8786 of the installer log (pacman db, then the
`ani-cli-git` clone), so finalize never ran. Not caused by code changes in
that run (readability pilot touched summary/finalize/03-install outline only).
Either size the matrix disks for the fleet profile or install a slimmer
profile in boot-smoke cells.

**Blocked by:** None (can start immediately)

**Status:** needs-triage

- [ ] Root cause: what fills the 40G (package cache, paru build dirs, ARC?)
- [ ] zfs-single-plain installs and boot-verifies green
