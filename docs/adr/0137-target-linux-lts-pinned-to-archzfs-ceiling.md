# ADR 0137: Target linux-lts pinned to the archzfs LTS ceiling

## Status
Accepted. Extends ADR 0023 and ADR 0024.

## Context
The installed system pulls `zfs-dkms` + `zfs-utils` (per-flavour, see
`lib/packages/filesystem.sh`) and DKMS-builds the ZFS module against the
`linux-lts` that pacstrap installs. `linux-lts` comes from the Arch core
mirror and is always current; archzfs's `zfs-dkms` source is released on
archzfs's own cadence and lags. When the mirror's `linux-lts` minor
version outruns what the current ZFS source supports, the DKMS build
fails to compile — observed as `vdev_disk.c: 'BIO_MAX_PAGES' undeclared`
with `linux-lts 6.18.52` against `zfs-dkms 2.4.4`.

The failure is intermittent by nature: it is a version race. Most
installs catch a moment where the mirror's `linux-lts` is at or below
what archzfs's ZFS source supports and build cleanly; occasionally
`linux-lts` has jumped ahead and the build fails. The ZFS Module Guard
(ADR 0024) correctly catches the bad build and aborts — but only after
pacstrap, and only as a report; the target kernel itself was never
constrained.

ADR 0023 already established that archzfs's prebuilt-kernel list is a
reliable proxy for "the current ZFS source compiles against this
kernel", and uses it to pick the *live-ISO* kernel. The *target* kernel
had no equivalent ceiling. That gap is this ADR's subject.

## Decision
1. **Pin the target `linux-lts` to the archzfs LTS ceiling.** Before
   pacstrap, host-side, resolve the newest `linux-lts` major.minor that
   archzfs ships a prebuilt `zfs-linux-lts` for, and pin
   `linux-lts` + `linux-lts-headers` to the newest patchlevel at or below
   that ceiling. The pinned pair is injected into the pacstrap package
   set. When the mirror's `linux-lts` already exceeds the ceiling, the
   exact version is pre-seeded from `archive.archlinux.org` (reusing the
   archive-fetch primitive from `lib/zfs/module.sh`).

2. **New owner module.** The ceiling lookup and pinned-version resolver
   live in `lib/packages/archzfs-kernel.sh` — the single source of "which
   `linux-lts` is archzfs-safe" — keeping `iso-resolver.sh` ISO-scoped.
   The lookup parses `zfs-linux-lts-*` assets specifically; the ISO
   resolver's existing lookup reads `zfs-linux-*` (the default kernel)
   and is a different ceiling.

3. **Granularity: major.minor ceiling, patch-tolerant.** Pin to the
   newest patchlevel of the archzfs-supported major.minor, matching the
   proven rule the ISO resolver already uses. The `BIO_MAX_PAGES` break
   was a minor-version jump, which a major.minor ceiling caps.

4. **Graceful degradation.** If the archzfs lookup is unreachable or
   returns no ceiling, proceed unpinned — exactly today's behavior — and
   let the ZFS Module Guard remain the backstop. A flaky lookup must
   never break an install that would otherwise succeed.

5. **lts token only.** The pin applies to the `lts` Kernel Selection
   token — the default, and the only flavour archzfs is guaranteed to
   track. Other flavours stay unpinned and guarded, unchanged.

## Considered alternatives
**Switch the lts target to the prebuilt `zfs-linux-lts`** (matched
kernel/zfs pair, no compile). The strongest guarantee, but reverses ADR
0023's "installer always builds via DKMS, never the prebuilt" and only
covers flavours with a prebuilt.

**Downgrade-and-retry on DKMS failure** (auto-remediation after
pacstrap). Rejected by ADR 0024 for hiding the real cause and adding
moving parts to the hottest install path; also wastes a full pacstrap
before retrying.

**Do nothing structural, improve the guard message.** Leaves the race in
place; the install still fails intermittently.

## Consequences
- The target `linux-lts` may be held back from the very newest patch
  release to stay at or below the archzfs ceiling. When mirror equals
  ceiling the pin is a no-op and the happy path is byte-identical.
- A held-back kernel is surfaced: a `warn` names the mirror version, the
  pinned version, and the archzfs-ceiling reason; the no-op case stays
  quiet.
- The pin closes the target-side gap ADR 0024's guard could only report.
  The guard remains as the backstop for the degraded (unpinned) path and
  for non-lts flavours.
- ADR 0023 still governs the live-ISO/bootstrap kernel; this ADR governs
  the installed-system `linux-lts`. The two ceilings are resolved
  independently (`zfs-linux-*` vs `zfs-linux-lts-*`).
