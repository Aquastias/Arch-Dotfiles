Status: done

# 03 — README "Prepare the install media" + CONTEXT Tools entry

## Parent

`.scratch/fetch-compatible-iso/PRD.md`

## What to build

Update the operator-facing docs so the blessed path is the
archzfs-Compatible ISO, not the latest Arch ISO.

- Restructure `.os/README.md` §2 (Quick Start):
  - New §2.1 "Prepare the install media" — on the current machine,
    from this repo, run `tools/fetch-iso.sh`, then flash the
    resulting ISO. Include a short "Why not the latest Arch ISO?"
    note (ZFS won't build against a kernel newer than archzfs tracks)
    referencing the archzfs-Compatible ISO term in CONTEXT.md.
  - Renumber the rest: §2.2 Boot the ISO (UEFI), §2.3 Connect to the
    internet, §2.4 Copy the scripts.
- Append `fetch-iso.sh` to the CONTEXT.md "Tools" glossary entry
  (one-line description; downloads the archzfs-Compatible ISO for USB
  prep).

The archzfs-Compatible ISO glossary term and ADR 0023 already exist —
do not duplicate them; reference them.

## Acceptance criteria

- [ ] README §2 has a new "Prepare the install media" step before
      "Boot the ISO", documenting `tools/fetch-iso.sh` and the flash
      step.
- [ ] A concise "why not the latest Arch ISO" note is present and
      points at the archzfs-Compatible ISO term.
- [ ] Subsequent Quick Start steps (boot / internet / copy scripts)
      are renumbered with no broken internal references.
- [ ] The CONTEXT.md "Tools" entry lists `fetch-iso.sh`.
- [ ] The documented `fetch-iso.sh` command matches the tool shipped
      in issue 02 (path, default output, arg).

## Blocked by

- Issue 02 (fetch-iso.sh tool).
