Status: ready-for-agent

# PRD: Secrets-activated sops Program

References: ADR 0025 (refines ADR 0006).

## Problem Statement

The operator noticed `go` installed on a laptop that uses no
secrets. `go` is a ~600 MB build toolchain pulled in only to
compile `ssh-to-age` inside the sops Program
(`programs/security/sops`). That Program also derives the Machine
Age Key and enables the SOPS Runtime Service.

It runs on every host because sops sits in Host Core's
`system_programs`. That contradicts ADR 0006, which makes secrets
optional — a host or user with no `secrets.json` is supposed to get
working defaults and none of the sops machinery. Today such hosts
still pay for the full sops runtime and carry `go` for nothing.

## Solution

Remove sops from Host Core. The Runner installs the sops Program
only when the host or one of its declared users ships a
`secrets.json` — the exact signal already computed by the Secrets
Module and recorded in install-state. `go` and the sops runtime
then land only on hosts that actually use secrets. Activation is
implicit (driven by secrets presence) and flows through the normal
System Program install path, so the mechanism stays uniform; only
the selection is conditional.

## User Stories

1. As an operator of a host with no secrets, I want neither `go`
   nor the sops runtime installed, so that the machine is not
   carrying a build toolchain it never uses.
2. As an operator of a host with secrets, I want the sops Program
   to run automatically, so that the Machine Age Key is derived and
   the SOPS Runtime Service is enabled without me listing sops
   anywhere.
3. As an operator, I want secrets presence alone to decide sops, so
   that I cannot have secrets configured but the runtime missing
   (the silent-decryption-break foot-gun).
4. As the installer maintainer, I want sops removed from Host Core
   `system_programs`, so that it is no longer forced on every host.
5. As the installer maintainer, I want the Runner to detect secrets
   from install-state (`.secrets.host` set, or `.secrets.users`
   non-empty), so that the decision reuses the Secrets Module's
   existing output rather than re-scanning the repo.
6. As the installer maintainer, I want sops selected through the
   normal System Program install path when secrets are present, so
   that there is no bespoke install branch to maintain.
7. As the installer maintainer, I want the secrets-presence check
   to be a pure, testable predicate, so that its behaviour is
   locked by bats.
8. As a future reader, I want the one System Program that is not
   declared in any host config documented as a deliberate
   exception, so that its implicit activation is not mistaken for a
   bug.

## Implementation Decisions

- **Host Core.** Drop `sops` from `system_programs`, leaving the
  other core System Programs intact.
- **Activation predicate.** A pure helper reads install-state and
  returns true when `.secrets.host` is set or `.secrets.users` is
  non-empty.
- **Runner.** When the predicate is true, the Runner adds `sops` to
  the System Program list it installs (deduplicated against any
  declared programs) and installs it via the existing
  per-system-program path. When false, sops is not installed and
  `go` is never pulled in.
- **sops Program unchanged.** `programs/security/sops` keeps
  building `ssh-to-age` via `go` and leaves `go` installed
  afterwards. No removal step.
- **Documented exception.** sops is the single System Program whose
  selection is implicit; this is recorded in `CONTEXT.md` against
  the "System Programs are declared" rule.

## Testing Decisions

Tests assert external behaviour, not internals.

- **Secrets predicate** (new bats, or extend an existing
  secrets/profiles suite): over install-state fixtures — `{}` →
  false; `.secrets.host` present → true; `.secrets.users` non-empty
  → true. Prior art: existing install-state fixtures used by the
  chroot suites.
- The end-to-end Runner path (which uses `arch-chroot`) is covered
  by the VM smoke tests, not a unit test; the unit-level guarantee
  is the pure predicate.

## Out of Scope

- Removing `go` after the build (left installed; may be revisited
  if build-dependency bloat becomes a concern).
- A manual sops opt-in with a validation guard — considered and
  rejected in favour of automatic activation.
- Any change to what `secrets.json` contains or to how the Secrets
  Module discovers and decrypts secrets.
- The `sops` repo package in host package lists, which only
  installs the `sops` binary and is unrelated to the Program.

## Further Notes

This refines ADR 0006: that ADR already declared secrets optional;
this work makes the runtime side honour it. The decision and its
single documented exception to the System Program rule are recorded
in ADR 0025 and `CONTEXT.md`.
