# Extract a shared archive.archlinux.org fetch helper

Status: ready-for-agent

## Parent

`.scratch/archzfs-lts-ceiling-pin/PRD.md`

## What to build

Pull the `archive.archlinux.org` package-download logic that currently lives
inside `lib/zfs/module.sh` (the exact-version headers fetch) out into a small
shared primitive: given a package name and an exact version, construct the
archive URL, download the package, and install it (mirror-first, archive as
fallback where that ordering already applies). `module.sh`'s bootstrap headers
path is refactored to call the shared helper — no behavior change on that path.

This is an enabler for the LTS ceiling pin (issue 02), which needs the same
archive fetch for `linux-lts` when the mirror has moved past the ceiling. One
implementation, DRY.

## Acceptance criteria

- [ ] A shared archive-fetch primitive exists, taking a package name + exact
      version and fetching/installing it from `archive.archlinux.org`.
- [ ] `lib/zfs/module.sh` uses the shared primitive for its headers download;
      the bootstrap DKMS path behaves exactly as before.
- [ ] bats cover the helper: kernel-release → pacman package-version string
      construction, archive URL layout, and the mirror-first / archive-fallback
      ordering.
- [ ] No change to any install-time behavior beyond the internal refactor.

## Blocked by

- None - can start immediately
