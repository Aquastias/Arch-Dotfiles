Status: ready-for-agent

# ZFS Module Guard (fail-fast, post-pacstrap)

## Parent

`.scratch/kernel-selection-and-zfs-guard/PRD.md` (ADR 0024).

## What to build

A fail-fast guard that runs host-side after the base system is
installed (pacstrap) and before chroot configuration begins. It
enumerates every kernel installed into the target — from each
kernel package's `pkgbase` marker — and verifies a loadable `zfs`
module exists for each, via `modinfo` inside the target root. If any
kernel lacks a ZFS module the install aborts immediately with a
message naming the offending kernel(s) and pointing at the archzfs
constraint. The guard never attempts a DKMS rebuild — it surfaces
the real cause rather than masking it.

The missing-module detection is a pure helper (module tree in →
set of kernels lacking ZFS out), kept separate from the thin
chroot/`error` wrapper, so it can be unit-tested in isolation.

This works against today's scalar `lts` selection and is the safety
net that later makes non-`lts` kernel selection safe.

## Acceptance criteria

- [ ] After base-system install and before chroot configuration, the
      installer verifies a loadable `zfs` module for every installed
      target kernel.
- [ ] Target kernels are enumerated from their `pkgbase` markers — no
      hardcoded kernel list.
- [ ] A pure helper returns the set of kernels missing a ZFS module
      given a module tree; new `zfs-verify.bats` covers: all present
      → empty set; one kernel lacking the module → that kernel.
- [ ] When a kernel lacks ZFS, the install aborts with a message
      naming the kernel and referencing the archzfs constraint; no
      DKMS rebuild is attempted.
- [ ] On the supported `lts` path the guard passes silently —
      behaviour unchanged.
- [ ] Test prior art followed: temp-dir path overrides as in
      `zfs-module.bats`.

## Blocked by

- None - can start immediately.
