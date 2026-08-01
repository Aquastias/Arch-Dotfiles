# Program kind is authoritative

Status: done

## Parent

.scratch/layered-software-model/PRD.md (R22)

## What to build

One lookup answers "what kind of program is this name?", and both guided
pickers obey it.

The program registry currently indexes name → `category/name` but drops the
`system` flag, so every consumer re-parses the program's `config.jsonc`. Extend
it to carry the flag and expose a single lookup returning `system`, `user`, or
`none` for an unknown name. Build once, reuse.

Then wire both program pickers to it. Today one unfiltered function feeds two
screens with **opposite** requirements: the host System Programs picker needs
`system: true` (3 of 15 qualify) and the User Editor's programs picker needs
`system: false` (12 of 15 qualify). Each currently offers all fifteen. The host
side builds a Config State that fails validation at Proceed, after the operator
has done all their other work; the user side silently no-ops when the host
already installs the program and aborts when it doesn't.

Prefactor for the exclusivity validator and the Package Resolver, both of which
need the same lookup.

## Acceptance criteria

- [ ] The registry carries each program's `system` flag alongside its category
- [ ] A kind lookup returns `system` for `grub`, `cups`, `sops`
- [ ] It returns `user` for `docker`, `podman`, `borg`, `firewalld`
- [ ] It returns `none` for a name with no program directory
- [ ] The registry is built once per run, not per lookup
- [ ] The host System Programs picker offers exactly the `system: true` programs
- [ ] The User Editor programs picker offers exactly the `system: false` programs
- [ ] Tests assert the *membership* of each picker's option set, not only the
      `[x]`/`[ ]` marking — marking-only assertions are what let this through
- [ ] A menu render no longer parses every program's `config.jsonc`

## Blocked by

None — can start immediately.
