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
- [ ] Boot still completes and the root pool imports (verified by the
      existing boot-verify VM smoke test).
- [ ] A pure emitter produces the hook-override content; a unit test
      asserts the bounded settle is present.
- [ ] The override keeps the stock trigger behavior (no device-discovery
      regression).

## Blocked by

None - can start immediately.
