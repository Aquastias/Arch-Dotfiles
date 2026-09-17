Status: done (option A: bare server user)

# `minimal` bare server user (HITL decision)

## Parent

`.scratch/program-config-architecture/PRD.md` (ADR 0134).

## What to build

Make `minimal` minimal end-to-end. Today it is bare at the host layer
(`packages.inherit: false`) but declares `aquastias`, a workstation user whose
own programs (`docker`, `teamspeak3`), groups (`docker`/`libvirt`/`kvm`), and
`sudo` survive — so a headless install still carries a workstation userland.

This slice is **HITL**: it needs a human architectural call before
implementation.

Decision to make (recommended: option A):

- **A.** `minimal` declares a dedicated **bare server user** (its own name,
  `programs_inherit: false`, minimal groups, no workstation programs) instead
  of reusing `aquastias`.
- **B.** Keep `aquastias` on `minimal` but set `programs_inherit: false` and
  drop its workstation groups/programs for this host.

## Acceptance criteria

- [ ] The A-vs-B decision is recorded (comment on this issue or a short ADR).
- [ ] `minimal` installs no workstation programs for any user (no `kitty`,
      `yazi`, `virt-manager`, `searxng`/`podman`, `pi`, `claude`, `docker`,
      `teamspeak3`).
- [ ] `minimal`'s user has only server-appropriate groups and no stray
      workstation `sudo`/group grants beyond what a server needs.
- [ ] CONTEXT.md `Minimal Profile` entry updated to reflect the end-to-end
      minimal state.

## Blocked by

- `03-programs-inherit-bareness.md`
