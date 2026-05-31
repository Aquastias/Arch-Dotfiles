# ADR 0025: sops is secrets-activated, not a Host Core program

## Status
Accepted. Refines ADR 0006.

## Context
ADR 0006 made secrets optional: a host or user with no `secrets.json`
gets working defaults (hardcoded user password, interactive root
prompt). But the sops Program — `programs/security/sops/install.sh` —
sat in Host Core's `system_programs`, so the Runner ran it on *every*
host. That install builds `ssh-to-age` from source via `go` (a ~600 MB
build toolchain) and derives the Machine Age Key from the SSH host key,
then enables the SOPS Runtime Service.

The result contradicted 0006: hosts with no secrets still paid for the
full sops runtime and carried `go`. The only signal that a host
actually needs sops — the presence of a `secrets.json` — was already
computed by the Secrets Module and threaded into `install-state.json`,
but was not consulted when deciding to run the Program.

## Decision
Remove sops from Host Core. The Runner installs the sops Program only
when the host or one of its declared users ships a `secrets.json` — the
same signal ADR 0006 uses for optionality, read from `install-state`'s
`.secrets`. Activation is implicit (driven by secrets presence) and is
routed through the normal system-program install path rather than a
bespoke branch, so the install mechanism stays uniform; only the
*selection* is conditional. `go` is consequently installed only on
secrets hosts, and is left in place after building `ssh-to-age`.

## Considered alternatives
**Manual opt-in plus a validation guard.** Hosts list `sops` in
`system_programs` explicitly, and the installer aborts if a host has
`secrets.json` but did not select sops. Explicit, but redundant —
secrets presence already determines need — and a forgotten opt-in
becomes a silent runtime-decryption break unless guarded.

**Keep sops in core, gate only the `go` build.** Narrower change, but
leaves the service half-configured on every host and splits the
Program's logic on an internal conditional.

## Consequences
- A host with no secrets gets neither the SOPS Runtime Service nor
  `go`.
- sops is the one System Program not declared in any host's
  `system_programs`; its activation is implicit. The "System Programs
  are declared in host config or Host Core" rule now has this single,
  documented exception (see `CONTEXT.md`).
- `go` remains installed on secrets hosts as a build-only dependency
  left behind — accepted for simplicity over a removal step.
