# ADR 0139: Ongoing archzfs LTS ceiling hold

## Status
Accepted. Extends ADR 0137; amends the pin's install-only scope.

## Context
ADR 0137 pins the target `linux-lts` to an archzfs-buildable version **at
install time**. It does nothing for later `pacman -Syu`: the installed system
has no hold, so an upgrade run during a skew window (mirror `linux-lts` has
jumped ahead of what archzfs's `zfs-dkms` can build) will happily upgrade
`linux-lts`, the DKMS build hook fails non-fatally, and the machine is left with
a `linux-lts` that has **no `zfs.ko`** — unbootable into its ZFS root on the next
boot. The Stray-Kernel warn hook (ADR 0038) only warns; it does not stop the bad
upgrade.

A pacman hook cannot express "upgrade everything except `linux-lts`": a
`PreTransaction` hook can only abort the whole transaction, which would block
every other package too. The only pacman-native way to hold one package while
upgrading the rest is `IgnorePkg`, which is read at transaction start and so must
be maintained **out of band**.

## Decision
1. **Hold via a marked `IgnorePkg` line, maintained by a systemd timer.** A
   timer (`archzfs-lts-hold.timer`, ~daily + shortly after boot) runs
   `lib/boot/lts-hold.sh`. When the mirror's newest `linux-lts` outruns the
   archzfs ceiling at the minor level, it writes a marked
   `IgnorePkg = linux-lts linux-lts-headers  # archzfs-lts-hold` line into
   `/etc/pacman.conf`; when archzfs catches up, it removes that line. The mark
   means an operator's own `IgnorePkg` is never touched.

2. **Hold at the installed version; never auto-install a kernel.** The timer only
   toggles `IgnorePkg` — it holds `linux-lts` where it is until archzfs catches
   up to the mirror, then releases so a normal `-Syu` moves it forward. It never
   performs an unattended kernel install.

3. **Non-blocking by construction.** `IgnorePkg` makes `pacman -Syu` skip
   `linux-lts`/headers and upgrade everything else. Nothing aborts.

4. **Fail-safe.** If the archzfs ceiling or the newest available version can't be
   determined (offline, lookup error), the timer leaves the current hold state
   untouched rather than guessing.

5. **Reuse the ceiling logic.** `lts-hold.sh` sources `archzfs-kernel.sh`
   (`archzfs_lts_pkgver` / `archzfs_pick_lts_version`), staged beside it at
   `/usr/local/lib/archzfs/`. Same definition of "archzfs-compatible" as the
   install pin, so the two can never disagree.

6. **Closest-available-compatible install fallback.** The install pin
   (ADR 0137) now, when the exact archzfs-built version can't be fetched, falls
   back to the newest `linux-lts` on the archive whose major.minor is at or below
   the ceiling — instead of degrading to unpinned. (`archzfs_pin_candidates`.)

Installed only when `lts` is in the Kernel Selection and the system has ZFS.

## Considered alternatives
**PreTransaction pacman hook that aborts** an incompatible `linux-lts` upgrade.
Simple, but blocks the *entire* `-Syu` — the operator explicitly wanted other
packages to keep upgrading.

**Auto-upgrade `linux-lts` to the newest compatible version** from the timer.
Fresher, but means unattended kernel installs from a background timer and more
moving parts; holding-at-installed is safer and self-releases.

**Do nothing (install-time pin only).** Leaves the upgrade footgun in place — a
single `-Syu` during a skew can strand the ZFS root kernel.

## Consequences
- During a skew window, `pacman -Syu` upgrades everything but `linux-lts`; the
  kernel jumps forward automatically once archzfs catches up (hold clears).
- The hold is only as fresh as the timer's last successful run; a manual `-Syu`
  immediately after a mirror bump but before the timer fires could still pull an
  incompatible kernel. The Stray-Kernel warn hook remains the backstop.
- Under impermanence, a runtime `IgnorePkg` edit may be rolled back on reboot,
  but the timer re-applies it shortly after boot (`OnBootSec`). Persisting it is
  out of scope here.
- ADR 0137 still governs the install-time pin; this ADR governs the installed
  system's ongoing upgrades. Both share one ceiling definition.
