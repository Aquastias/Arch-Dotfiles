# VM acceptance: arch-combined completes (pin + stray tolerance)

Status: ready-for-agent

## Parent

`.scratch/stray-kernel-install-tolerance/PRD.md`

## What to build

The acceptance gate: a **forced-skew `arch-combined` recreation** that completes
the install successfully — proving both fixes end-to-end in one run.

- The archzfs LTS ceiling pin (ADR 0137) fires under
  `ARCHZFS_LTS_CEILING_OVERRIDE` (lts held back to an archive version, e.g.
  `6.12.75`), the pinned kernel is fetched from the archive and built.
- The wine-pulled stray `linux` (rolling) is tolerated (ADR 0138): the guard
  warns instead of aborting, `mkinitcpio` skips its preset, and the install
  reaches completion (`===INSTALLER-EXIT-0===`).

The VM installs the local working tree via the local-serve (dumb-HTTP bare repo
on the libvirt gateway pointed at by `REPO_URL`), so uncommitted-to-remote code
is what runs.

## Acceptance criteria

- [ ] A forced-skew `arch-combined` recreation completes the install (clean exit
      sentinel; no `No ZFS kernel module` abort).
- [ ] `install.log` shows the lts pin firing (held back to the override version)
      and the stray `linux` tolerated (guard warn, preset skipped).
- [ ] The selected `linux-lts` has a `zfs.ko`; the stray `linux` has none and no
      initramfs.

## Blocked by

- `.scratch/stray-kernel-install-tolerance/issues/01-tolerate-stray-kernels-at-install.md`
