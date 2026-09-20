# PRD: Ongoing archzfs LTS ceiling hold

Status: ready-for-agent

Anchored by [[ADR 0139]] (Ongoing archzfs LTS ceiling hold), extending
[[ADR 0137]] (install-time pin).

## Problem Statement

The install-time pin (ADR 0137) gets a working install, but does nothing for
later `pacman -Syu`. During a skew window (mirror `linux-lts` outruns archzfs's
`zfs-dkms`), `-Syu` upgrades `linux-lts`, the DKMS build fails non-fatally, and
the box is left with a `linux-lts` that has no `zfs.ko` — unbootable into its ZFS
root. Only a non-blocking warn hook exists as backstop.

## Solution

A systemd timer holds `linux-lts` (via a marked `IgnorePkg` line) whenever the
mirror's newest lts outruns the archzfs ceiling, and clears the hold when archzfs
catches up. `-Syu` then holds the kernel but upgrades everything else. The hold
reuses the install pin's ceiling logic, holds at the installed version (no
unattended kernel installs), and is fail-safe when offline. Separately, the
install pin gains a closest-available-compatible fallback when the exact
archzfs-built version can't be fetched.

## User Stories

1. As an operator, I want `pacman -Syu` during a skew window to hold `linux-lts`
   but upgrade everything else, so a routine upgrade never strands my ZFS root
   kernel without a `zfs.ko`.
2. As an operator, I want the hold to clear automatically once archzfs catches
   up, so my kernel resumes normal upgrades with no manual step.
3. As an operator, I don't want the kernel silently reinstalled by a background
   timer — only held or released.
4. As an operator, I want my own `IgnorePkg` entries left untouched.
5. As an operator on an offline box, I want the hold state left as-is rather than
   guessed.
6. As an operator, if the exact archzfs-built `linux-lts` isn't fetchable at
   install, I want the closest available compatible version used instead of an
   unpinned install.

## Implementation Decisions

- `lib/boot/lts-hold.sh`: marked-`IgnorePkg` editor (pure `lts_hold_set`) +
  runtime that reads the archzfs ceiling (`archzfs_lts_pkgver`) and the newest
  available `linux-lts` (throwaway db sync), then holds/releases.
- `archzfs-lts-hold.timer`/`.service` installed + enabled for ZFS hosts that
  selected `lts`; runtime + `archzfs-kernel.sh` + `archive.sh` staged to
  `/usr/local/lib/archzfs/`.
- `archzfs_pin_candidates` + candidate-trying `_archzfs_lts_pin_build_repo`: the
  closest-available-compatible install fallback.

## Testing Decisions

- bats: `lts_hold_set` (add/remove/idempotent/operator-line-safe);
  `archzfs_pin_candidates` (<= ceiling, newest-first); build-repo candidate
  fallback (exact, fallback, none). Mirrors `stray-kernel.bats`/`resolver.bats`.
- VM: on the existing `arch-combined` VM (no recreate) — deploy the hold script,
  force a low ceiling → confirm `linux-lts` held + others upgradable; real
  ceiling → confirm hold cleared.

## Out of Scope

- Auto-upgrading `linux-lts` to the newest compatible version (hold-at-installed
  chosen).
- A PreTransaction abort hook (blocks other packages — rejected).
- Persisting the runtime `IgnorePkg` edit across impermanence rollback.

## Further Notes

A manual `-Syu` between a mirror bump and the next timer run could still pull an
incompatible kernel; the Stray-Kernel warn hook remains the backstop.
