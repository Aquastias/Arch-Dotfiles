# Default disk passphrase constant + `--unattended` precedence tier

Status: ready-for-agent

## Parent

.scratch/guided-encryption-editor/PRD.md
ADR: docs/adr/0059-guided-encryption-editor.md

## What to build

One shared constant holding the default disk passphrase `12345678`, and a new
precedence tier that lets the back end use it when the install is unattended.

Installing an encrypted Host Profile unattended currently blocks forever: the
run promises to bypass every interactive confirmation, then reaches a tty
passphrase prompt because nothing non-guided supplies a passphrase. Add a tier
between the Secrets Manifest and the prompt:

1. the `INSTALL_ENC_PASSPHRASE` preset — test/VM seam
2. the Secrets Manifest's encryption passphrase
3. **unattended → the default constant** — new
4. fall through to the interactive tty prompt

Tier 3 is gated on the unattended flag on purpose. An interactive profile
install must still prompt: silently encrypting a disk with a known default the
operator was never shown is worse than asking. The chroot layer already gates
root's account default on the same flag — follow that precedent.

The ladder is **not** extracted into a separate resolver. It is already driven
end to end by an existing precedence test block, including the fall-through to
the prompt, so a new seam would duplicate coverage rather than create it. Add
the tier where the ladder already lives, and extend that existing block.

The constant must be safe to re-source; a bare readonly reassignment aborts on a
second source. Its comment records why it is eight characters: ZFS
`keyformat=passphrase` rejects anything shorter at pool creation, which is what
makes the existing five-character default unusable.

## Acceptance criteria

- [ ] A shared constant defines the default disk passphrase as `12345678`
- [ ] The constant's definition is safe to source more than once
- [ ] A comment beside it records the ZFS ≥8-character reason for its length
- [ ] The preset still takes precedence over the Secrets Manifest
- [ ] The Secrets Manifest takes precedence over the unattended default
- [ ] An unattended run with no preset and no manifest resolves to `12345678`
- [ ] An interactive run with no preset and no manifest still reaches the prompt
- [ ] Encryption being off still short-circuits before any collection
- [ ] One assertion pins the default against ZFS's ≥8-character floor
- [ ] The new cases extend the existing precedence test block
- [ ] No new test seam is introduced for the ladder
- [ ] Account password defaults are untouched by this ticket
- [ ] Installing an encrypted Host Profile unattended no longer blocks

## Blocked by

None — can start immediately
