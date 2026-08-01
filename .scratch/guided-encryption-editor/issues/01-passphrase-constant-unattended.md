# Default disk passphrase constant + `--unattended` back-end tier

Status: ready-for-agent

## Parent

.scratch/guided-encryption-editor/PRD.md
ADR: docs/adr/0059-guided-encryption-editor.md

## What to build

One shared constant holding the default disk passphrase `12345678`, and a new
precedence tier that lets the back end use it when the install is unattended.

The passphrase precedence ladder currently lives inline inside the routine that
also prompts on the tty and assigns a global. Extract the ladder as a **pure
resolver**: given the preset environment value, the Secrets Manifest path, and
whether the run is unattended, return the resolved passphrase together with the
source it came from. The caller keeps the tty prompt and the global assignment,
so nothing downstream changes shape.

Resolution order:

1. the `INSTALL_ENC_PASSPHRASE` preset — test/VM seam
2. the Secrets Manifest's encryption passphrase
3. **unattended → the default constant** — new
4. fall through to the interactive tty prompt

Tier 3 is gated on the unattended flag on purpose. An interactive profile
install must still prompt: silently encrypting a disk with a known default the
operator was never shown is worse than asking. The chroot layer already gates
root's account default on the same flag — follow that precedent.

The constant must be safe to re-source (a bare readonly reassignment aborts
under a second source). Its comment records *why* it is eight characters: ZFS
`keyformat=passphrase` rejects anything shorter at pool creation, which is what
makes the existing five-character default unusable.

This slice fixes a standalone bug: an unattended install of an encrypted Host
Profile blocks forever on a tty prompt inside a run that promised to bypass
every interactive confirmation.

## Acceptance criteria

- [ ] A shared constant defines the default disk passphrase as `12345678`
- [ ] The constant's definition is safe to source more than once
- [ ] A comment beside it records the ZFS ≥8-character reason for its length
- [ ] The precedence ladder is a pure function: no tty reads, no globals set
- [ ] The resolver reports both the resolved value and its source
- [ ] The preset takes precedence over the Secrets Manifest
- [ ] The Secrets Manifest takes precedence over the unattended default
- [ ] An unattended run with no preset and no manifest resolves to `12345678`
- [ ] An interactive run with no preset and no manifest still reaches the prompt
- [ ] The resolved default satisfies the ≥8-character floor ZFS enforces
- [ ] Account password defaults are untouched by this slice
- [ ] Installing an encrypted Host Profile unattended no longer blocks

## Blocked by

None - can start immediately
