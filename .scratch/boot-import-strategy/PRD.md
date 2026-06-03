# Boot-time ZFS import: stop uevent settle from hanging boot

Status: ready-for-agent

See ADR 0030 (Boot-time ZFS import strategy), ADR 0028 (stable device
paths). Glossary: Chroot Configuration Module, Single Entry Point.

## Problem Statement

On a multi-disk machine with a slow spinning HDD, boot intermittently
stalls — sometimes at the initramfs `:: Triggering uevents...` line,
sometimes at "A start job is running for systemd-udev-settle" in the
booted system, where the data-pool import service fails with "Dependency
failed." Both are the same root cause: a global "settle every uevent"
barrier waiting on a device whose coldplug is slow. The stall clears
itself after the default 120 s timeout, so boot is reliably slow rather
than reliably fast.

## Solution

Treat the initramfs as the authoritative ZFS importer — it already
imports the root pool (by stable by-id scan) and the other cached pools
— and turn the post-boot import services into a genuinely non-blocking
fallback by removing their dependency on the deprecated
`systemd-udev-settle`. Separately, bound the initramfs settle so a slow
device can no longer hang boot past 30 s. Pools still import; the boot
hangs disappear.

## User Stories

1. As a person booting a multi-disk machine, I want boot not to hang on
   uevents, so that my system comes up quickly and reliably.
2. As an owner of a slow HDD, I want a slow device coldplug to not block
   boot indefinitely, so that boot proceeds within seconds.
3. As an operator, I want the ZFS import services to not depend on the
   deprecated `systemd-udev-settle`, so that a slow settle can't fail my
   pool imports.
4. As a person, I want the "A start job is running for udev-settle"
   stall gone, so that I'm not staring at a multi-minute hang.
5. As an operator, I want my data pools still imported at boot, so that
   decoupling from settle doesn't cost me auto-import.
6. As an operator, I want a pool that isn't yet in the cache to still be
   imported by a post-boot fallback, so that a pool created after
   install still comes up.
7. As an operator, I want the bounded settle to be a fixed, sane value,
   so that there is no new knob to misconfigure.
8. As a maintainer, I want the unit drop-ins and the hook override
   produced by testable pure functions, so that I can assert their
   content without booting a VM.
9. As an operator, I want the initramfs to remain the real importer, so
   that boot-time import doesn't regress.
10. As a future contributor, I want the decision not to migrate to a
    systemd-based initramfs recorded, so that the trade-off is clear.

## Implementation Decisions

- **Decouple the post-boot import services from
  `systemd-udev-settle`.** Ship systemd drop-ins (written by the Chroot
  Configuration Module's ZFS step) that remove the
  `Requires=`/`After=systemd-udev-settle` relationship from both the
  cache-import and scan-import services. They remain oneshot,
  best-effort, and never gate boot — matching what OpenZFS upstream did.
- **Bound the initramfs settle.** Override the initramfs `udev` runtime
  hook (written before the initramfs is built) so it runs the same
  device-trigger pair followed by a settle bounded to 30 s instead of
  the unbounded default. The value is fixed, not a config field.
- **Initramfs stays authoritative.** The root pool is found by the by-id
  scan and the archzfs hook retries the import, so a 30 s cap is safe on
  a reasonably-fast root disk. Reliable cache-driven import depends on
  ADR 0028's stable by-id paths.
- **Pure content emitters.** The drop-in text and the hook-override text
  are produced by pure functions, so the directives can be asserted in
  isolation.

## Testing Decisions

- A good test asserts the **external output** of the emitters: that the
  drop-in removes the `systemd-udev-settle` dependency and that the hook
  override caps the settle at the chosen timeout — behavior, not file
  mechanics.
- **Unit-test (bats) the two emitters.**
- **Prior art:** `chroot-initcpio.bats` (the `HOOKS=` line emitter and
  initcpio behavior), `chroot-configure.bats` (chroot service config).
- **Integration:** the existing VM smoke tests already power-cycle into
  the installed system and wait for a first-boot sentinel; they continue
  to validate that boot completes.

## Out of Scope

- Migrating to a systemd-based initramfs (rejected: too invasive given
  the archzfs `zfs` hook, the encryption passphrase prompt, and the
  impermanence rollback hook).
- Diagnosing or quieting a specific slow device (hardware-specific, not
  an installer concern).
- Making the settle timeout a configurable field.

## Further Notes

- The `udev` hook override shadows the stock hook; it is kept minimal
  (same trigger pair, bounded settle) so it rarely needs syncing with
  upstream. Recorded in ADR 0030.
