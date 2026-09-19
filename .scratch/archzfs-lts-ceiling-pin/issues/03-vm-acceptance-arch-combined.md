# VM acceptance: arch-combined recreation must succeed

Status: ready-for-agent

## Parent

`.scratch/archzfs-lts-ceiling-pin/PRD.md`

## What to build

The acceptance gate proving the pin actually changes what pacstrap installs.
Recreate the `arch-combined` VM end-to-end; the install must complete
successfully — no ZFS Module Guard abort, no DKMS `BIO_MAX_PAGES` failure.

The skew is live today (mirror `linux-lts` 6.18.52 > archzfs ceiling), so a
plain recreation genuinely exercises the pin path now. Additionally drive the
forced-skew override seam (fake-low ceiling) to prove the pin fires and the
build succeeds even once archzfs catches up and the natural skew disappears —
so this gate stays a real regression test.

## Acceptance criteria

- [ ] A full `arch-combined` VM recreation completes the install successfully.
- [ ] The install log shows the held-back `warn` (pin fired) when the mirror
      exceeds the ceiling, or a clean silent no-op when mirror == ceiling.
- [ ] A recreation with the forced-skew override set to a fake-low ceiling still
      completes: the pin holds `linux-lts` back and DKMS builds cleanly.
- [ ] No regression on the happy path — an install where mirror == ceiling
      behaves as before.

## Blocked by

- `.scratch/archzfs-lts-ceiling-pin/issues/02-archzfs-lts-ceiling-pin.md`
