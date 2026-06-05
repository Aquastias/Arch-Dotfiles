# Bounded initramfs udev settle

Status: ready-for-agent

## Parent

`.scratch/boot-import-strategy/PRD.md`

## What to build

Override the initramfs `udev` runtime hook so it runs the same
device-trigger pair followed by a settle bounded to 30 seconds, instead
of the unbounded default. A device whose coldplug is slow can then no
longer stall boot at the "Triggering uevents" stage beyond the cap. The
override is written before the initramfs is built, and the bound is a
fixed value (not a config field). Safe because the root pool is found by
the by-id scan with the archzfs hook's own import retry.

## Acceptance criteria

- [ ] The installed system's initramfs caps the udev settle at the
      chosen timeout.
- [x] Boot still completes and the root pool imports (verified by the
      existing boot-verify VM smoke test).
- [x] A pure emitter produces the hook-override content; a unit test
      asserts the bounded settle is present.
- [x] The override keeps the stock trigger behavior (no device-discovery
      regression).

## Blocked by

None - can start immediately.

## Comments

- Implemented (TDD): `lib/chroot/initcpio.sh` — pure emitter
  `_initcpio_udev_override` prints an `/etc/initcpio/hooks/udev` that
  shadows the stock hook: same `udevd` start + `udevadm trigger`
  subsystems/devices pair, then `udevadm settle --timeout=30` (fixed
  bound, not a config field). Thin writer `_initcpio_write_udev_override
  <root>` installs it under `etc/initcpio/hooks/udev`; called before
  `mkinitcpio -P` so the override is baked into the image.
- 3 new `chroot-initcpio.bats` cases (settle capped at 30s, trigger pair
  preserved, writer shadows the stock hook). Full bats green,
  `shellcheck -x -P SCRIPTDIR` clean.
- Unit ACs done. Remaining (boxes 1-2): a VM run to confirm the installed
  initramfs caps the settle and boot still completes — covered by the
  existing boot-verify VM smoke test; no libvirt on this dev host. Status
  stays `ready-for-agent` for a host that can run it.
- 2026-06-06: ran boot-verify on real KVM at HEAD. Boot reaches
  `FIRSTBOOT-OK`; initramfs `udev` hook runs ("Triggering uevents") with
  no device-discovery regression and rpool imports. Box 2 ticked (boot
  completes + root pool imports). Box 1 ("caps settle at 30s") left open:
  a clean boot can't distinguish a bounded from an unbounded settle, so
  the cap value needs an in-guest read of the installed
  `/etc/initcpio/hooks/udev` (or a test-only serial diagnostic dump) —
  not runnable offline here (no zpool/sudo).
