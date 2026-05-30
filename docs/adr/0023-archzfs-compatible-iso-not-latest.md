# ADR 0023: archzfs-Compatible ISO, not the latest Arch

## Status
Accepted.

## Context
The installer has no ZFS module on the official Arch ISO, so
`01-bootstrap-zfs.sh` builds ZFS via DKMS against the running
live-ISO kernel. DKMS can only build when the current ZFS source
supports that kernel. The latest Arch ISO routinely ships a kernel
newer than archzfs tracks — and the live mirror can move to a newer
kernel mid-month than the ISO itself — so building ZFS on the latest
ISO fails or lands a module for the wrong kernel.

Concrete incident: a latest ISO running kernel `7.0.x` against ZFS
`2.4.2` either failed to build or produced a module for a kernel that
was not the one running, leaving `modprobe zfs` with nothing to load.

archzfs publishes prebuilt `zfs-linux` packages only for kernels it
has tested. That prebuilt-kernel list is therefore a reliable proxy
for "the current ZFS source compiles against this kernel" — even
though the installer itself always uses DKMS, never the prebuilt.

## Decision
Both install paths target the newest *archived* Arch ISO whose kernel
major.minor matches an archzfs-supported kernel, resolved by
`iso_resolver_get_zfs_compatible` in `lib/iso-resolver.sh` (the
archzfs-Compatible ISO; see `CONTEXT.md`).

- VM harness (`.os/vm/_harness.sh`) already resolves this ISO.
- `.os/tools/fetch-iso.sh` resolves + downloads it for bare-metal USB
  prep, verifying sha256 against the release's `sha256sums.txt`.
- `.os/README.md` directs operators to `fetch-iso.sh`, not
  `archlinux.org/download`.

## Considered alternatives
**Use the latest Arch ISO.** The obvious path, and what operators
reach for by default — but it is exactly what fails when the ISO
kernel outruns archzfs.

**Custom archiso bundling a matching prebuilt ZFS.** Removes the
DKMS build at install time, but means maintaining and hosting a
custom ISO pipeline — far more upkeep than picking an archived ISO.

**`zfs-dkms-git` to track bleeding-edge kernels.** Sometimes builds
against newer kernels, but trades a reproducible release for a moving
target that can break unpredictably mid-install.

## Consequences
- The install ISO lags the latest Arch release by up to a few weeks.
- Kernel and security updates land *after* install via the normal
  `pacman -Syu`; DKMS rebuilds ZFS against `linux-lts` on the
  installed system, so currency is regained immediately post-install.
- Both paths depend on the archzfs GitHub release (supported-kernel
  list) and the archlinux.org releng JSON (available archived ISOs);
  an outage of either surfaces as a clear resolver error.
- Operators cannot simply grab today's ISO — the README and tooling
  make the compatible ISO the default, removing the foot-gun.
